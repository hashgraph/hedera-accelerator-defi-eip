// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {FeeConfiguration} from "../common/FeeConfiguration.sol";

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

/**
 * @title Basic Vault
 *
 * The contract which represents a custom Vault.
 */
contract BasicVault is ERC4626, ERC165, FeeConfiguration, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    using Bits for uint256;

    // Min reward amount considired in case of small reward
    uint256 private constant MIN_REWARD = 1;

    // Reward tokens
    address[] private _rewardTokens;

    // Info by user
    mapping(address => UserInfo) private _userContribution;

    // Reward info by user
    mapping(address => RewardsInfo) private _tokensRewardInfo;

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

    // Using if owner adds reward which exceeds max token amount
    error MaxRewardTokensAmount();

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
        IERC20 _underlying,
        string memory _name,
        string memory _symbol,
        FeeConfig memory _feeConfig,
        address _vaultRewardController,
        address _feeConfigController
    ) payable ERC20(_name, _symbol) ERC4626(_underlying) Ownable(msg.sender) {
        __FeeConfiguration_init(_feeConfig, _vaultRewardController, _feeConfigController);
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
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        afterDeposit(assets, receiver);
    }

    /**
     * @dev Mints shares to receiver by depositing assets of underlying tokens.
     *
     * @param shares The amount of shares to send.
     * @param receiver The receiver of tokens.
     * @return assets The amount of tokens to receive.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        afterDeposit(assets, receiver);
    }

    /**
     * @dev Burns shares from owner and sends assets of underlying tokens to receiver.
     *
     * @param assets The amount of assets.
     * @param receiver The staking token receiver.
     * @param owner The owner of shares.
     * @return shares The amount of shares to burn.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        beforeWithdraw(assets, receiver);

        shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @dev Redeems shares for underlying assets.
     *
     * @param shares The amount of shares.
     * @param receiver The staking token receiver.
     * @param owner The shares owner.
     * @return assets The amount of shares to burn. beforeWithdraw(amount, receiver);
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Updates user state according to withdraw inputs.
     *
     * @param _amount The amount of shares.
     */
    function beforeWithdraw(uint256 _amount, address rewardReceiver) internal {
        claimAllReward(0, rewardReceiver);
        _userContribution[msg.sender].sharesAmount -= _amount;
    }

    /**
     * @dev Updates user state after deposit and mint calls.
     *
     * @param _amount The amount of shares.
     */
    function afterDeposit(uint256 _amount, address rewardReceiver) internal {
        if (!_userContribution[msg.sender].exist) {
            uint256 rewardTokensSize = _rewardTokens.length;
            for (uint256 i; i < rewardTokensSize; i++) {
                address token = _rewardTokens[i];
                _userContribution[msg.sender].lastClaimedAmountT[token] = _tokensRewardInfo[token].amount;
            }
            _userContribution[msg.sender].sharesAmount = _amount;
            _userContribution[msg.sender].exist = true;
            _userContribution[msg.sender].lastLockedTime = block.timestamp;
        } else {
            if (_userContribution[msg.sender].sharesAmount == 0) {
                _userContribution[msg.sender].sharesAmount += _amount;
            } else {
                claimAllReward(0, rewardReceiver);
                _userContribution[msg.sender].sharesAmount += _amount;
                _userContribution[msg.sender].lastLockedTime = block.timestamp;
            }
        }
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
        require(_token != asset() && _token != address(this), "HederaVault: Reward and Staking tokens cannot be same");
        require(_token != address(0), "HederaVault: Invalid reward token");
        require(totalAssets() != 0, "HederaVault: No token staked yet");

        if (_rewardTokens.length == 10) revert MaxRewardTokensAmount();

        uint256 perShareRewards = _amount.mulDivDown(1, totalAssets());
        RewardsInfo storage rewardInfo = _tokensRewardInfo[_token];
        if (!rewardInfo.exist) {
            _rewardTokens.push(_token);
            rewardInfo.exist = true;
            rewardInfo.amount = perShareRewards;
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            _tokensRewardInfo[_token].amount += perShareRewards;
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
        emit RewardAdded(_token, _amount);
    }

    /**
     * @dev Claims all pending reward tokens for the caller.
     *
     * @param _startPosition The starting index in the reward token list from which to begin claiming rewards.
     * @return The index of the start position after the last claimed reward and the total number of reward tokens.
     */
    function claimAllReward(uint256 _startPosition, address receiver) public returns (uint256, uint256) {
        uint256 _rewardTokensSize = _rewardTokens.length;
        address _feeToken = feeConfig.token;
        address _rewardToken;
        uint256 _reward;

        require(_rewardTokensSize != 0, "HederaVault: No reward tokens exist");

        for (uint256 i = _startPosition; i < _rewardTokensSize; i++) {
            _rewardToken = _rewardTokens[i];

            _reward = getUserReward(msg.sender, _rewardToken);
            _userContribution[msg.sender].lastClaimedAmountT[_rewardToken] = _tokensRewardInfo[_rewardToken].amount;

            // Fee management
            if (_feeToken != address(0)) {
                IERC20(_rewardToken).safeTransfer(receiver, _deductFee(_reward));
            } else {
                IERC20(_rewardToken).safeTransfer(receiver, _reward);
            }
        }
        return (_startPosition, _rewardTokensSize);
    }

    /**
     * @dev Returns rewards for a user with fee considering.
     *
     * @param _user The user address.
     * @param _rewardToken The reward address.
     * @return unclaimedAmount The calculated rewards.
     */
    function getUserReward(address _user, address _rewardToken) public view returns (uint256 unclaimedAmount) {
        RewardsInfo storage _rewardInfo = _tokensRewardInfo[_rewardToken];
        uint256 perShareAmount = _rewardInfo.amount;

        UserInfo storage cInfo = _userContribution[_user];
        uint256 userStakingTokenTotal = cInfo.sharesAmount;
        uint256 perShareClaimedAmount = cInfo.lastClaimedAmountT[_rewardToken];
        uint256 perShareUnclaimedAmount = perShareAmount - perShareClaimedAmount;

        // Add precision to consider small rewards
        unclaimedAmount = (perShareUnclaimedAmount * 1e18) / userStakingTokenTotal;
        unclaimedAmount = unclaimedAmount / 1e18;

        if (feeConfig.feePercentage > 0) {
            uint256 currentFee = _calculateFee(unclaimedAmount, feeConfig.feePercentage);
            unclaimedAmount -= currentFee;
        }

        if (unclaimedAmount == 0) unclaimedAmount = MIN_REWARD;
    }

    /**
     * @dev Returns all rewards for a user with fee considering.
     *
     * @param _user The user address.
     * @return _rewards The rewards array.
     */
    function getAllRewards(address _user) public view returns (uint256[] memory _rewards) {
        uint256 rewardsSize = _rewardTokens.length;
        _rewards = new uint256[](rewardsSize);

        for (uint256 i = 0; i < rewardsSize; i++) {
            _rewards[i] = getUserReward(_user, _rewardTokens[i]);
        }
    }

    /**
     * @dev Returns reward tokens addresses.
     *
     * @return Reward tokens.
     */
    function getRewardTokens() public view returns (address[] memory) {
        return _rewardTokens;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC165) returns (bool) {
        return interfaceId == type(IERC4626).interfaceId || super.supportsInterface(interfaceId);
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
