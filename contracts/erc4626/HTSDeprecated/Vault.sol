// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v2;

import {ERC20} from ".././ERC20.sol";
import {IERC4626} from ".././IERC4626.sol";
import {IHRC} from "../../common/hedera/IHRC.sol";

import {FeeConfiguration} from "../../common/FeeConfiguration.sol";

import {FixedPointMathLib} from ".././FixedPointMathLib.sol";
import {SafeTransferLib} from ".././SafeTransferLib.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "../../common/safe-HTS/SafeHTS.sol";
import "../../common/safe-HTS/IHederaTokenService.sol";

/**
 * @title Hedera Vault
 *
 * The contract which represents a custom Vault with Hedera HTS support.
 */
contract HederaVault is IERC4626, FeeConfiguration, Ownable, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Bits for uint256;

    // Staking token
    ERC20 private immutable _asset;

    // Share token
    address private _share;

    // Staked amount
    uint256 public assetTotalSupply;

    // Reward tokens
    address[] public rewardTokens;

    // Info by user
    mapping(address => UserInfo) public userContribution;

    // Reward info by user
    mapping(address => RewardsInfo) public tokensRewardInfo;

    // User Info struct
    struct UserInfo {
        uint256 sharesAmount;
        uint256 lastLockedTime;
        mapping(address => uint256) lastClaimedAmountT;
        bool exist;
    }

    // Rewards Info struct
    struct RewardsInfo {
        uint256 amount;
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
     * @notice RewardAdded event.
     * @dev Emitted when permissioned user adds reward to the Vault.
     *
     * @param rewardToken The address of reward token.
     * @param amount The added reward token amount.
     */
    event RewardAdded(address indexed rewardToken, uint256 amount);

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param _underlying The address of the _asset token.
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

        _asset = _underlying;

        _createTokenWithContractAsOwner(_name, _symbol, _underlying);
    }

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
        _share = SafeHTS.safeCreateFungibleToken(newToken, 0, _underlying.decimals());
        emit CreatedToken(_share);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deposits staking token to the Vault and returns shares.
     *
     * @param assets The amount of staking token to send.
     * @param receiver The shares receiver address.
     * @return shares The amount of shares to receive.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        require(receiver != address(0), "HederaVault: Invalid receiver address");
        if ((shares = previewDeposit(assets)) == 0) revert ZeroShares(assets);

        _asset.safeTransferFrom(msg.sender, address(this), assets);

        // Mint and transfer share
        SafeHTS.safeMintToken(_share, uint64(assets), new bytes[](0));
        SafeHTS.safeTransferToken(_share, address(this), receiver, int64(uint64(assets)));

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets);
    }

    /**
     * @dev Mints shares to receiver by depositing assets of underlying tokens.
     *
     * @param shares The amount of shares to send.
     * @param receiver The receiver of tokens.
     * @return amount The amount of tokens to receive.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 amount) {
        require(receiver != address(0), "HederaVault: Invalid receiver address");
        if ((amount = previewMint(shares)) == 0) revert ZeroShares(shares);

        // Mint and transfer share
        SafeHTS.safeMintToken(_share, uint64(amount), new bytes[](0));
        SafeHTS.safeTransferToken(_share, address(this), receiver, int64(uint64(amount)));

        emit Deposit(msg.sender, receiver, amount, shares);

        _asset.safeTransferFrom(msg.sender, address(this), amount);

        afterDeposit(amount);
    }

    /**
     * @dev Burns shares from owner and sends assets of underlying tokens to receiver.
     *
     * @param amount The amount of assets.
     * @param receiver The staking token receiver.
     * @param from The owner of shares.
     * @return shares The amount of shares to burn.
     */
    function withdraw(
        uint256 amount,
        address receiver,
        address from
    ) public override nonReentrant returns (uint256 shares) {
        require(receiver != address(0), "HederaVault: Invalid receiver address");
        require(from != address(0), "HederaVault: Invalid from address");
        require((shares = previewWithdraw(amount)) != 0, "HederaVault: Zero assets");
        require(userContribution[from].sharesAmount >= shares, "HederaVault: Not enough share on the balance");

        beforeWithdraw(amount);

        // Transfer and burn share
        SafeHTS.safeTransferToken(_share, from, address(this), int64(uint64(amount)));
        SafeHTS.safeBurnToken(_share, uint64(amount), new int64[](0));

        _asset.safeTransfer(receiver, amount);

        emit Withdraw(from, receiver, amount, shares);
    }

    /**
     * @dev Redeems shares for underlying assets.
     *
     * @param shares The amount of shares.
     * @param receiver The staking token receiver.
     * @param from The shares owner.
     * @return amount The amount of shares to burn.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address from
    ) public override nonReentrant returns (uint256 amount) {
        require(receiver != address(0), "HederaVault: Invalid receiver address");
        require(from != address(0), "HederaVault: Invalid from address");
        require((amount = previewRedeem(shares)) != 0, "HederaVault: Zero assets");
        require(userContribution[from].sharesAmount >= shares, "HederaVault: Not enough share on the balance");

        beforeWithdraw(amount);

        // Transfer and burn share
        SafeHTS.safeTransferToken(_share, from, address(this), int64(uint64(amount)));
        SafeHTS.safeBurnToken(_share, uint64(amount), new int64[](0));

        _asset.safeTransfer(receiver, amount);

        emit Withdraw(from, receiver, amount, shares);
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Updates user state according to withdraw inputs.
     *
     * @param _amount The amount of shares.
     */
    function beforeWithdraw(uint256 _amount) internal {
        claimAllReward(0);
        userContribution[msg.sender].sharesAmount -= _amount;
        assetTotalSupply -= _amount;
    }

    /**
     * @dev Updates user state after deposit and mint calls.
     *
     * @param _amount The amount of shares.
     */
    function afterDeposit(uint256 _amount) internal {
        if (!userContribution[msg.sender].exist) {
            uint256 rewardTokensSize = rewardTokens.length;
            for (uint256 i; i < rewardTokensSize; i++) {
                address token = rewardTokens[i];
                userContribution[msg.sender].lastClaimedAmountT[token] = tokensRewardInfo[token].amount;
                IHRC(token).associate();
            }
            userContribution[msg.sender].sharesAmount = _amount;
            userContribution[msg.sender].exist = true;
            userContribution[msg.sender].lastLockedTime = block.timestamp;
            assetTotalSupply += _amount;
        } else {
            claimAllReward(0);
            userContribution[msg.sender].sharesAmount += _amount;
            userContribution[msg.sender].lastLockedTime = block.timestamp;
            assetTotalSupply += _amount;
        }
    }

    /*///////////////////////////////////////////////////////////////
                        ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns reward tokens addresses.
     *
     * @return Reward tokens.
     */
    function getRewardTokens() public view returns (address[] memory) {
        return rewardTokens;
    }

    /**
     * @dev Returns Share token address.
     */
    function share() public view override returns (address) {
        return _share;
    }

    /**
     * @dev Returns Asset token address.
     */
    function asset() public view override returns (address) {
        return address(_asset);
    }

    /**
     * @dev Returns amount of assets on the contract balance.
     *
     * @return _asset balance of this contract.
     */
    function totalAssets() public view override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /**
     * @dev Calculates amount of assets that can be received for user share balance.
     *
     * @param user The user address.
     * @return The amount of underlying assets equivalent to the user's shares.
     */
    function assetsOf(address user) public view override returns (uint256) {
        return previewRedeem(balanceOf[user]);
    }

    /**
     * @dev Calculates amount of assets per share.
     *
     * @return The _asset amount per share.
     */
    function assetsPerShare() public view override returns (uint256) {
        return previewRedeem(10 ** decimals);
    }

    /**
     * @dev Returns the maximum amount of underlying assets that can be deposited by user.
     *
     * @return The maximum assets amount that can be deposited.
     */
    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Returns the maximum amount of shares that can be minted by user.
     *
     * @return The maximum shares amount that can be minted.
     */
    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Calculates the maximum amount of assets that can be withdrawn by user.
     *
     * @param user The user address.
     * @return The maximum amount of assets that can be withdrawn.
     */
    function maxWithdraw(address user) public view override returns (uint256) {
        return assetsOf(user);
    }

    /**
     * @dev Returns the maximum number of shares that can be redeemed by user.
     *
     * @param user The user address.
     * @return The maximum number of shares that can be redeemed.
     */
    function maxRedeem(address user) public view override returns (uint256) {
        return balanceOf[user];
    }

    /**
     * @dev Calculates the amount of shares that will be minted for a given assets amount.
     *
     * @param amount The amount of underlying assets to deposit.
     * @return shares The estimated amount of shares that can be minted.
     */
    function previewDeposit(uint256 amount) public view override returns (uint256 shares) {
        uint256 supply = totalSupply;

        return supply == 0 ? amount : amount.mulDivDown(1, totalAssets());
    }

    /**
     * @dev Calculates the amount of underlying assets equivalent to a given shares amount.
     *
     * @param shares The shares amount to be minted.
     * @return amount The estimated assets amount.
     */
    function previewMint(uint256 shares) public view override returns (uint256 amount) {
        uint256 supply = totalSupply;

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), totalSupply);
    }

    /**
     * @dev Calculates the amount of shares that would be burned for a given assets amount.
     *
     * @param amount The amount of underlying assets to withdraw.
     * @return shares The estimated shares amount that can be burned.
     */
    function previewWithdraw(uint256 amount) public view override returns (uint256 shares) {
        uint256 supply = _asset.balanceOf(address(this));

        return supply == 0 ? amount : amount.mulDivUp(supply, totalAssets());
    }

    /**
     * @dev Calculates the amount of underlying assets equivalent to a specific number of shares.
     *
     * @param shares The shares amount to redeem.
     * @return amount The estimated assets amount that can be redeemed.
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 amount) {
        uint256 supply = totalSupply;

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), totalSupply);
    }

    /*///////////////////////////////////////////////////////////////
                        REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Adds reward to the Vault.
     *
     * @param _token The reward token address.
     * @param _amount The amount of reward token to add.
     */
    function addReward(address _token, uint256 _amount) external payable onlyRole(VAULT_REWARD_CONTROLLER_ROLE) {
        require(_amount != 0, "HederaVault: Amount can't be zero");
        require(assetTotalSupply != 0, "HederaVault: No token staked yet");
        require(_token != address(_asset) && _token != _share, "HederaVault: Reward and Staking tokens cannot be same");
        require(_token != address(0), "HederaVault: Invalid reward token");

        if (rewardTokens.length == 10) revert MaxRewardTokensAmount();

        uint256 perShareRewards = _amount.mulDivDown(1, assetTotalSupply);
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
    function claimAllReward(uint256 _startPosition) public payable override returns (uint256, uint256) {
        uint256 rewardTokensSize = rewardTokens.length;
        address _token = feeConfig.token;

        require(rewardTokensSize != 0, "HederaVault: No reward tokens exist");

        uint256 reward;
        address token;
        for (uint256 i = _startPosition; i < rewardTokensSize; i++) {
            token = rewardTokens[i];
            reward = getUserReward(msg.sender, token);
            
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
    function getUserReward(address _user, address _rewardToken) public view override returns (uint256 unclaimedAmount) {
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
     * @dev Returns all rewards for a user with fee considering.
     *
     * @param _user The user address.
     * @return _rewards The rewards array.
     */
    function getAllRewards(address _user) public view returns (uint256[] memory _rewards) {
        uint256 rewardsSize = rewardTokens.length;
        _rewards = new uint256[](rewardsSize);

        for (uint256 i = 0; i < rewardsSize; i++) {
            _rewards[i] = getUserReward(_user, rewardTokens[i]);
        }
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
