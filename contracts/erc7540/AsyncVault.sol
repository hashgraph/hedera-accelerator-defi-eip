// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v2;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC7540} from "./interfaces/IERC7540.sol";

import {ERC20} from "../erc4626/ERC20.sol";
import {FeeConfiguration} from "../common/FeeConfiguration.sol";

import {FixedPointMathLib} from "../erc4626/FixedPointMathLib.sol";
import {SafeTransferLib} from "../erc4626/SafeTransferLib.sol";

import "../common/safe-HTS/SafeHTS.sol";
import "../common/safe-HTS/IHederaTokenService.sol";

/**
 * @title Async Vault
 *
 * The contract which represents a custom Vault with Hedera HTS support
 * and async deposit/redeem functionality.
 */
contract AsyncVault is IERC7540, ERC20, FeeConfiguration, ReentrancyGuard, Ownable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Bits for uint256;

    // Staking token
    ERC20 public immutable asset;

    // Share token
    address public share;

    // Staked amount
    uint256 public assetTotalSupply;

    // Reward tokens
    address[] public rewardTokens;

    mapping(address => uint256) public pendingDepositBalance;

    mapping(address => uint256) public claimableDepositBalance;

    mapping(address => mapping(uint256 requestId => uint256)) public deposits;

    mapping(address => mapping(uint256 requestId => uint256)) public redeems;

    mapping(address => UserInfo) public userContribution;

    mapping(address => RewardsInfo) public tokensRewardInfo;

    uint256 public nextDepositRequestId;
    uint256 public nextRedeemRequestId;

    struct RewardsInfo {
        uint256 amount;
        bool exist;
    }

    struct UserInfo {
        uint256 sharesAmount;
        mapping(address => uint256) lastClaimedAmountT;
        bool exist;
    }

    /**
     * @notice CreatedToken event.
     * @dev Emitted after contract initialization, when share token was deployed.
     *
     * @param createdToken The address of share token.
     */
    event CreatedToken(address indexed createdToken);

    /**
     * @notice ClaimDeposit event.
     * @dev Emitted after user claims the requested deposit amount.
     *
     * @param requestId The ID of a deposit request.
     * @param owner The owner address.
     * @param operator The operator address.
     * @param assets The deposited asset amount.
     * @param shares The claimed share amount.
     */
    event ClaimDeposit(
        uint256 indexed requestId,
        address indexed owner,
        address indexed operator,
        uint256 assets,
        uint256 shares
    );

    /**
     * @notice ClaimDeposit event.
     * @dev Emitted after user claims the requested redeem amount.
     *
     * @param requestId The ID of a redeem request.
     * @param owner The owner address.
     * @param operator The operator address.
     * @param assets The redeemed asset amount.
     * @param shares The share amount.
     */
    event ClaimRedeem(
        uint256 indexed requestId,
        address indexed owner,
        address indexed operator,
        uint256 assets,
        uint256 shares
    );

    /**
     * @notice DecreaseDepositRequest event.
     * @dev Emitted after user decreases the requested deposit amount.
     *
     * @param requestId The ID of a deposit request.
     * @param owner The owner address.
     * @param previousRequestedAssets The previous request amount.
     * @param newRequestedAssets The new request amount.
     */
    event DecreaseDepositRequest(
        uint256 indexed requestId,
        address indexed owner,
        uint256 indexed previousRequestedAssets,
        uint256 newRequestedAssets
    );

    /**
     * @notice RewardAdded event.
     * @dev Emitted when permissioned user adds reward to the Vault.
     *
     * @param rewardToken The address of reward token.
     * @param amount The added reward token amount.
     */
    event RewardAdded(address indexed rewardToken, uint256 amount);

    /**
     * @notice The error is emitted when a user try to make a new redeem request
     * but there is lack of shares.
     */
    error MaxRedeemRequestExceeded(address controller, uint256 shares, uint256 maxShares);

    /**
     * @notice The error is emitted when a user try to make a new deposit request
     * and the deposited amount is grater than deposit limit.
     */
    error MaxDepositRequestExceeded(address controller, uint256 assets, uint256 maxDeposit);

    /**
     * @notice The error is emitted when a user try to make a new request
     * on behalf of someone else.
     */
    error ERC7540CantRequestDepositOnBehalfOf();

    /**
     * @notice The error is emitted when owner reaches the max reward tokens limit
     * during adding new one.
     */
    error MaxRewardTokensAmount();

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param _underlying The address of the asset token.
     * @param _name The share token name.
     * @param _symbol The share token symbol.
     * @param _feeConfig The fee configuration struct.
     * @param _vaultRewardController The Vault reward controller user.
     * @param _feeConfigController The fee config controller user.
     */
    constructor(
        ERC20 _underlying,
        string memory _name,
        string memory _symbol,
        FeeConfig memory _feeConfig,
        address _vaultRewardController,
        address _feeConfigController
    ) payable ERC20(_name, _symbol, _underlying.decimals()) Ownable(msg.sender) {
        __FeeConfiguration_init(_feeConfig, _vaultRewardController, _feeConfigController);

        asset = _underlying;
        nextDepositRequestId = 1;
        nextRedeemRequestId = 1;

        _createTokenWithContractAsOwner(_name, _symbol, _underlying);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/REDEEM ASYNC LOGIC
    //////////////////////////////////////////////////////////////*/

    function _createTokenWithContractAsOwner(string memory _name, string memory _symbol, ERC20 _underlying) internal {
        SafeHTS.safeAssociateToken(address(_underlying), address(this));
        uint256 supplyKeyType;
        uint256 adminKeyType;

        IHederaTokenService.KeyValue memory supplyKeyValue;
        supplyKeyType = supplyKeyType.setBit(4);
        supplyKeyValue.delegatableContractId = address(this);

        IHederaTokenService.KeyValue memory adminKeyValue;
        adminKeyType = adminKeyType.setBit(0);
        adminKeyValue.delegatableContractId = address(this);

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](2);

        keys[0] = IHederaTokenService.TokenKey(supplyKeyType, supplyKeyValue);
        keys[1] = IHederaTokenService.TokenKey(adminKeyType, adminKeyValue);

        IHederaTokenService.Expiry memory expiry;
        expiry.autoRenewAccount = address(this);
        expiry.autoRenewPeriod = 8000000;

        IHederaTokenService.HederaToken memory newToken;
        newToken.name = _name;
        newToken.symbol = _symbol;
        newToken.treasury = address(this);
        newToken.expiry = expiry;
        newToken.tokenKeys = keys;
        share = SafeHTS.safeCreateFungibleToken(newToken, 0, _underlying.decimals());
        emit CreatedToken(share);
    }

    /**
     * @dev Updates state for tracking rewards data.
     *
     * @param shares The minted amount of shares.
     */
    function _afterClaimDeposit(uint256 shares) internal {
        if (!userContribution[msg.sender].exist) {
            uint256 rewardTokensSize = rewardTokens.length;
            for (uint256 i; i < rewardTokensSize; i++) {
                address token = rewardTokens[i];
                userContribution[msg.sender].lastClaimedAmountT[token] = tokensRewardInfo[token].amount;
            }
            userContribution[msg.sender].sharesAmount = shares;
            userContribution[msg.sender].exist = true;
        } else {
            userContribution[msg.sender].sharesAmount += shares;
        }
    }

    /**
     * @dev Updates state according to the validated redeem request.
     *
     * @param shares The amount of shares to redeem.
     * @param operator The operator address.
     * @param owner The owner address.
     */
    function _createRedeemRequest(uint256 shares, address operator, address owner) internal {
        redeems[owner][nextDepositRequestId] = shares;

        emit RedeemRequested(operator, owner, nextDepositRequestId, msg.sender, shares);

        nextRedeemRequestId++;
    }

    /**
     * @dev Burns shares and transfers assets to the owner.
     *
     * @param owner The request creator.
     * @param receiver The receiver address.
     * @param requestId The ID of the request.
     */
    function _claimRedeem(address owner, address receiver, uint256 requestId) internal returns (uint256 assets) {
        uint256 amountToRedeem = redeems[owner][requestId];
        assets = previewClaimRedeem(owner, requestId);

        redeems[owner][requestId] = 0;
        userContribution[owner].sharesAmount -= amountToRedeem;

        assetTotalSupply -= assets;

        _burn(address(this), amountToRedeem);
        asset.safeTransfer(owner, assets);

        emit ClaimRedeem(requestId, owner, receiver, assets, amountToRedeem);
    }

    /**
     * @dev Mints shares and transfers to the owner.
     *
     * @param owner The request creator.
     * @param receiver The receiver address.
     * @param requestId The ID of the request.
     */
    function _claimDeposit(address owner, address receiver, uint256 requestId) internal returns (uint256 shares) {
        uint256 assets = deposits[owner][requestId];
        shares = previewClaimDeposit(owner, requestId);

        deposits[owner][requestId] = 0;
        claimableDepositBalance[owner] -= assets;

        _afterClaimDeposit(shares);

        SafeHTS.safeMintToken(share, uint64(shares), new bytes[](0));
        SafeHTS.safeTransferToken(share, address(this), msg.sender, int64(uint64(shares)));

        emit ClaimDeposit(requestId, owner, receiver, assets, shares);
    }

    /**
     * @dev Updates state according to the validated deposit request.
     *
     * @param assets The amount of assets to deposit.
     * @param operator The operator address.
     * @param owner The owner address.
     */
    function _createDepositRequest(uint256 assets, address operator, address owner) internal {
        deposits[owner][nextDepositRequestId] = assets;
        pendingDepositBalance[owner] += assets;

        emit DepositRequested(operator, owner, nextDepositRequestId, msg.sender, assets);

        nextDepositRequestId++;
    }

    /**
     * @dev Creates a new pending async deposit request.
     *
     * @param assets The amount of assets to deposit.
     * @param operator The operator address.
     * @param owner The owner address.
     */
    function requestDeposit(uint256 assets, address operator, address owner) external override {
        require(assets != 0, "AsyncVault: Invalid asset amount");
        require(operator != address(0) && owner != address(0), "AsyncVault: Invalid owner address");

        if (msg.sender != owner) {
            revert ERC7540CantRequestDepositOnBehalfOf();
        }

        if (assets > maxDepositRequest(owner)) {
            revert MaxDepositRequestExceeded(operator, assets, maxDepositRequest(owner));
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _createDepositRequest(assets, operator, owner);
    }

    /**
     * @dev Creates a new pending async redeem request.
     *
     * @param shares The amount of shares to redeem.
     * @param operator The operator address.
     * @param owner The owner address.
     */
    function requestRedeem(uint256 shares, address operator, address owner) external override {
        require(shares != 0, "AsyncVault: Invalid share amount");
        require(operator != address(0) && owner != address(0), "AsyncVault: Invalid owner address");

        if (shares > maxRedeemRequest(owner)) {
            revert MaxRedeemRequestExceeded(operator, shares, maxRedeemRequest(owner));
        }

        SafeHTS.safeTransferToken(share, msg.sender, address(this), int64(uint64(shares)));

        // Create a new request
        _createRedeemRequest(shares, operator, owner);
    }

    /**
     * @dev Adds reward to the Vault.
     *
     * @param _token The reward token address.
     * @param _amount The amount of reward token to add.
     */
    function addReward(address _token, uint256 _amount) external payable onlyRole(VAULT_REWARD_CONTROLLER_ROLE) {
        require(_amount != 0, "Vault: Amount can't be zero");
        require(assetTotalSupply != 0, "Vault: No token staked yet");
        require(_token != address(asset) && _token != share, "Vault: Reward and Staking tokens cannot be same");

        if (rewardTokens.length == 10) revert MaxRewardTokensAmount();

        uint256 perShareRewards = _amount.mulDivDown(totalSupply + 1, totalAssets() + 1);
        RewardsInfo storage rewardInfo = tokensRewardInfo[_token];
        if (!rewardInfo.exist) {
            rewardTokens.push(_token);
            rewardInfo.exist = true;
            rewardInfo.amount = perShareRewards;
            SafeHTS.safeAssociateToken(_token, address(this));
            ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            tokensRewardInfo[_token].amount += perShareRewards;
            ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
        emit RewardAdded(_token, _amount);
    }

    /**
     * @dev Claims all pending reward tokens for the caller.
     *
     * @param _startPosition The starting index in the reward token list from which to begin claiming rewards.
     * @return The index of the start position after the last claimed reward and the total number of reward tokens.
     */
    function claimAllReward(uint256 _startPosition) public payable returns (uint256, uint256) {
        uint256 rewardTokensSize = rewardTokens.length;
        address _token = feeConfig.token;

        for (uint256 i = _startPosition; i < rewardTokensSize && i < _startPosition + 10; i++) {
            uint256 reward;
            address token = rewardTokens[i];
            reward = (tokensRewardInfo[token].amount - userContribution[msg.sender].lastClaimedAmountT[token])
                .mulDivDown(1, userContribution[msg.sender].sharesAmount);
            userContribution[msg.sender].lastClaimedAmountT[token] = tokensRewardInfo[token].amount;
            SafeHTS.safeTransferToken(token, address(this), msg.sender, int64(uint64(reward)));
            if (_token != address(0)) _deductFee(reward);
        }
        return (_startPosition, rewardTokensSize);
    }

    /**
     * @dev Returns rewards for a user with fee considering.
     *
     * @param _user The user address.
     * @param _rewardToken The reward address.
     * @return unclaimedAmount The calculated rewards.
     */
    function getUserReward(address _user, address _rewardToken) public view returns (uint256 unclaimedAmount) {
        RewardsInfo storage _rewardInfo = tokensRewardInfo[_rewardToken];

        uint256 perShareAmount = _rewardInfo.amount;
        UserInfo storage cInfo = userContribution[_user];
        uint256 userStakingTokenTotal = cInfo.sharesAmount;
        uint256 perShareClaimedAmount = cInfo.lastClaimedAmountT[_rewardToken];
        uint256 perShareUnclaimedAmount = perShareAmount - perShareClaimedAmount;
        unclaimedAmount = perShareUnclaimedAmount.mulDivDown(1, userStakingTokenTotal);

        if (feeConfig.feePercentage > 0) {
            uint256 currentFee = _calculateFee(unclaimedAmount, feeConfig.feePercentage);
            unclaimedAmount -= currentFee;
        }
    }

    /**
     * @dev Shows user how many shares he'll get after claim the request.
     *
     * @param owner The owner of the deposit request.
     * @param requestId The request ID.
     * @return The amount of shares to get.
     */
    function previewClaimDeposit(address owner, uint256 requestId) public view returns (uint256) {
        return _convertToShares(deposits[owner][requestId]);
    }

    /**
     * @dev Shows user how many assets he'll get after claim the request.
     * @param owner The owner of redeem request.
     * @param requestId The ID of the request.
     * @return The amount of assets to get.
     */
    function previewClaimRedeem(address owner, uint256 requestId) public view returns (uint256) {
        return _convertToAssets(redeems[owner][requestId]);
    }

    /**
     * @dev Claims the pending deposit request.
     *
     * @param receiver The address of the request creator.
     * @param requestId The ID of the request to claim.
     * @return shares The amount of claimed shares.
     */
    function claimDeposit(address receiver, uint256 requestId) external returns (uint256 shares) {
        require(receiver != address(0), "AsyncVault: Invalid receiver address");
        return _claimDeposit(msg.sender, receiver, requestId);
    }

    /**
     * @dev Claims the pending redeem request.
     *
     * @param receiver The address of the request creator.
     * @param requestId The address of the user that requested the redeem.
     * @return assets The amount of claimed assets.
     */
    function claimRedeem(address receiver, uint256 requestId) external returns (uint256 assets) {
        require(receiver != address(0), "AsyncVault: Invalid receiver address");
        return _claimRedeem(_msgSender(), receiver, requestId);
    }

    /**
     * @dev Decreases the requested deposit amount.
     *
     * @param assets The amount of assets to decrease.
     * @param requestId The ID of the deposit request.
     */
    function decreaseDepositRequest(uint256 assets, uint256 requestId) external {
        uint256 oldBalance = deposits[msg.sender][requestId];

        require(assets <= oldBalance && assets != 0, "AsyncVault: Invalid amount to decrease requested amount");

        deposits[msg.sender][requestId] -= assets;
        pendingDepositBalance[msg.sender] -= assets;

        asset.safeTransfer(msg.sender, assets);

        emit DecreaseDepositRequest(requestId, msg.sender, oldBalance, deposits[msg.sender][requestId]);
    }

    /**
     * @dev Converts the assets into shares.
     *
     * @param assets The amount of assets to convert.
     * @return The amount of shares.
     */
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        return assets.mulDivDown(totalSupply + 1, totalAssets() + 1);
    }

    /**
     * @dev Converts the shares into assets.
     *
     * @param shares The amount of shares to convert.
     * @return The amount of shares.
     */
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        return shares.mulDivDown(totalAssets() + 1, totalSupply + 1);
    }

    /**
     * @dev Returns amount of assets on the contract balance.
     *
     * @return Asset balance of this contract.
     */
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @dev Returns the max possible amount of assets to deposit.
     */
    function maxDepositRequest(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Returns the max possible amount of shares to redeem.
     */
    function maxRedeemRequest(address owner) public view returns (uint256) {
        return balanceOf[owner];
    }

    /**
     * @dev Returns the pending asset amount from the deposit request.
     *
     * @param owner The owner of the request.
     * @param requestId The ID of the request.
     * @return assets The assets amount.
     */
    function pendingDepositRequest(address owner, uint256 requestId) external view override returns (uint256 assets) {
        return deposits[owner][requestId];
    }

    /**
     * @dev Returns the pending asset amount from the redeem request.
     *
     * @param owner The owner of the request.
     * @param requestId The ID of the request.
     * @return shares The shares amount.
     */
    function pendingRedeemRequest(address owner, uint256 requestId) external view override returns (uint256 shares) {
        return redeems[owner][requestId];
    }

    /**
     * @dev Returns reward tokens addresses.
     *
     * @return Reward tokens.
     */
    function getRewardTokens() public view returns (address[] memory) {
        return rewardTokens;
    }
}

library Bits {
    uint256 internal constant ONE = uint256(1);

    /**
     * @dev Sets the bit at the given 'index' in 'self' to '1'.
     *
     * @return Returns the modified value.
     */
    function setBit(uint256 self, uint8 index) internal pure returns (uint256) {
        return self | (ONE << index);
    }
}
