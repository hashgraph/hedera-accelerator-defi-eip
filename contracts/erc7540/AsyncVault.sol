// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "../erc4626/FixedPointMathLib.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {ERC7540} from "./ERC7540.sol";
import {IERC7540} from "./interfaces/IERC7540.sol";

import {FeeConfiguration} from "../common/FeeConfiguration.sol";

/**
 * @title Async Vault
 * @author Hashgraph
 *
 * The contract which represents a custom Vault with async deposit/redeem support.
 */
contract AsyncVault is ERC7540, ERC165, FeeConfiguration, Ownable {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    // Min reward amount considired in case of small reward
    uint8 private constant MIN_REWARD = 1;

    // Total duration of vesting (after cliff date) expressed in seconds
    uint32 private _unlockDuration;

    // Cliff date expressed in seconds
    uint32 public _cliff;

    // Reward tokens
    address[] private _rewardTokens;

    // Timestamp of deposit lock
    mapping(address => uint256) private _depositLockCheckPoint;

    // Info by user
    mapping(address => UserInfo) private _userContribution;

    // Reward info by user
    mapping(address => RewardsInfo) private _tokensRewardInfo;

    // User Info struct
    struct UserInfo {
        uint256 sharesAmount;
        uint256 totalLocked;
        uint256 totalReleased;
        uint256 depositLockCheckpoint;
        mapping(address => uint256) lastClaimedAmountT;
        bool exist;
    }

    // Rewards Info struct
    struct RewardsInfo {
        uint256 amount;
        bool exist;
    }

    /**
     * @notice SetSharesLockTime event.
     * @dev Emitted when permissioned user updates shares lock time.
     *
     * @param time The shares lock period.
     */
    event SetSharesLockTime(uint32 time);

    /**
     * @notice RewardAdded event.
     * @dev Emitted when permissioned user adds reward to the Vault.
     *
     * @param rewardToken The address of reward token.
     * @param amount The added reward token amount.
     */
    event RewardAdded(address indexed rewardToken, uint256 amount);

    // Thrown when owner adds reward which exceeds max token amount
    error MaxRewardTokensAmount();

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param underlying_ The address of the asset token.
     * @param name_ The share token name.
     * @param symbol_ The share token symbol.
     * @param feeConfig_ The fee configuration struct.
     * @param vaultRewardController_ The Vault reward controller user.
     * @param feeConfigController_ The fee config controller user.
     * @param cliff_ The cliff date expressed in seconds.
     * @param unlockDuration_ The unlock duration expressed in seconds.
     */
    constructor(
        IERC20 underlying_,
        string memory name_,
        string memory symbol_,
        FeeConfig memory feeConfig_,
        address vaultRewardController_,
        address feeConfigController_,
        uint32 cliff_,
        uint32 unlockDuration_
    ) payable ERC7540(underlying_) ERC20(name_, symbol_) Ownable(msg.sender) {
        __FeeConfiguration_init(feeConfig_, vaultRewardController_, feeConfigController_);

        _cliff = cliff_;
        _unlockDuration = unlockDuration_;
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ERC7540
     */
    function requestDeposit(uint256 assets, address controller, address owner) public override {
        uint256 mintedShares = convertToShares(assets);
        super.requestDeposit(assets, controller, owner);
        // fulfill the request directly
        _fulfillDepositRequest(controller, assets, mintedShares);
    }

    /**
     * @dev Mints shares Vault shares to receiver by claiming the Request of the controller.
     *
     * @param assets The amount of staking token to send.
     * @param to The shares receiver.
     * @return shares The minted shares.
     */
    function deposit(uint256 assets, address to) public override returns (uint256 shares) {
        return deposit(assets, to, msg.sender);
    }

    /**
     * @dev Mints shares to receiver by claiming the Request of the controller.
     *
     * @param assets The assets to deposit.
     * @param to The shares receiver.
     * @param controller The Request controller.
     * @return shares The shares amount.
     */
    function deposit(uint256 assets, address to, address controller) public override returns (uint256 shares) {
        shares = super.deposit(assets, to, controller);
        _afterDeposit(assets, to);
    }

    /**
     * @dev Mints shares to receiver by claiming the Request of the controller.
     *
     * @param shares The shares amount to mint.
     * @param to The shares receiver.
     * @return assets The assets amount.
     */
    function mint(uint256 shares, address to) public override returns (uint256 assets) {
        return mint(shares, to, msg.sender);
    }

    /**
     * @dev Mints shares to receiver by claiming the Request of the controller.
     *
     * @param shares The shares amount to mint.
     * @param to The shares receiver.
     * @param controller The request controller.
     * @return assets The assets amount.
     */
    function mint(uint256 shares, address to, address controller) public override returns (uint256 assets) {
        assets = super.mint(shares, to, controller);
        _afterDeposit(assets, to);
    }

    /**
     * @inheritdoc ERC7540
     */
    function requestRedeem(uint256 shares, address controller, address owner) public override {
        super.requestRedeem(shares, controller, owner);
        _fulfillRedeemRequest(controller, shares, convertToAssets(shares));
    }

    /**
     * @dev Redeems shares for assets, ensuring all settled requests are fulfilled.
     *
     * @param shares The amount of shares to redeem.
     * @param receiver The assets receiver.
     * @param controller The redemption controller.
     * @return assets The amount of assets redeemed.
     */
    function redeem(uint256 shares, address receiver, address controller) public override returns (uint256 assets) {
        return super.redeem(shares, receiver, controller);
    }

    /**
     * @dev Withdraws assets, ensuring all settled requests are fulfilled.
     *
     * @param assets The amount of assets to withdraw.
     * @param receiver The assets receiver.
     * @param controller The withdrawal controller.
     * @return shares The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address controller) public override returns (uint256 shares) {
        return super.withdraw(assets, receiver, controller);
    }

    /**
     * @dev Sets shares lock time.
     *
     * @param time The lock period.
     */
    function setSharesLockTime(uint32 time) external onlyOwner {
        _unlockDuration = time;
        emit SetSharesLockTime(time);
    }

    /**
     * @dev Override to include '_beforeWithdraw' hook.
     */
    function _withdraw(
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    ) internal override returns (uint256 assetsReturn, uint256 sharesReturn) {
        _beforeWithdraw(assets, receiver);
        return super._withdraw(assets, shares, receiver, controller);
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Updates user state according to withdraw inputs.
     *
     * @param _amount The amount of shares.
     * @param _rewardReceiver The reward receiver.
     */
    function _beforeWithdraw(uint256 _amount, address _rewardReceiver) internal {
        claimAllReward(0, _rewardReceiver);
        _userContribution[msg.sender].sharesAmount -= _amount;
        _userContribution[msg.sender].totalReleased += _amount;
    }

    /**
     * @dev Updates user state after deposit and mint calls.
     *
     * @param _amount The amount of shares.
     * @param _rewardReceiver The reward receiver.
     */
    function _afterDeposit(uint256 _amount, address _rewardReceiver) internal {
        if (!_userContribution[msg.sender].exist) {
            uint256 rewardTokensSize = _rewardTokens.length;
            for (uint256 i; i < rewardTokensSize; i++) {
                address token = _rewardTokens[i];
                _userContribution[msg.sender].lastClaimedAmountT[token] = _tokensRewardInfo[token].amount;
            }
            _userContribution[msg.sender].sharesAmount = _amount;
            _userContribution[msg.sender].totalLocked = _amount;
            _userContribution[msg.sender].depositLockCheckpoint = block.timestamp;
            _userContribution[msg.sender].exist = true;
        } else {
            if (_userContribution[msg.sender].sharesAmount == 0) {
                _userContribution[msg.sender].sharesAmount += _amount;
                _userContribution[msg.sender].totalLocked += _amount;
                _userContribution[msg.sender].depositLockCheckpoint = block.timestamp;
            } else {
                claimAllReward(0, _rewardReceiver);
                _userContribution[msg.sender].sharesAmount += _amount;
                _userContribution[msg.sender].totalLocked += _amount;
                _userContribution[msg.sender].depositLockCheckpoint = block.timestamp;
            }
        }
    }

    function _unlocked(address account) private view returns (uint256 unlocked) {
        UserInfo storage info = _userContribution[account];

        uint256 currentlyLocked = info.totalLocked - info.totalReleased;

        uint256 lockStart = info.depositLockCheckpoint + _cliff;

        if (block.timestamp < lockStart || currentlyLocked == 0) return 0;

        uint256 lockEnd = lockStart + _unlockDuration;

        if (block.timestamp >= lockEnd) {
            unlocked = currentlyLocked;
        } else {
            uint256 elapsed = block.timestamp - lockStart;
            unlocked = (currentlyLocked * elapsed) / _unlockDuration;
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
        require(_amount != 0, "AsyncVault: Amount can't be zero");
        require(_token != asset() && _token != address(this), "AsyncVault: Reward and Staking tokens cannot be same");
        require(_token != address(0), "AsyncVault: Invalid reward token");
        require(totalAssets() != 0, "AsyncVault: No token staked yet");

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
     * @param _receiver The reward receiver.
     * @return The index of the start position after the last claimed reward and the total number of reward tokens.
     */
    function claimAllReward(uint256 _startPosition, address _receiver) public returns (uint256, uint256) {
        uint256 _rewardTokensSize = _rewardTokens.length;
        address _feeToken = feeConfig.token;
        address _rewardToken;
        uint256 _reward;

        require(_rewardTokensSize != 0, "AsyncVault: No reward tokens exist");

        for (uint256 i = _startPosition; i < _rewardTokensSize; i++) {
            _rewardToken = _rewardTokens[i];

            _reward = getUserReward(msg.sender, _rewardToken);
            _userContribution[msg.sender].lastClaimedAmountT[_rewardToken] = _tokensRewardInfo[_rewardToken].amount;

            // Fee management
            if (_feeToken != address(0)) {
                IERC20(_rewardToken).safeTransfer(_receiver, _deductFee(_reward));
            } else {
                IERC20(_rewardToken).safeTransfer(_receiver, _reward);
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

        if (userStakingTokenTotal == 0) return 0;

        uint256 perShareClaimedAmount = cInfo.lastClaimedAmountT[_rewardToken];
        uint256 perShareUnclaimedAmount = perShareAmount - perShareClaimedAmount;

        // Add precision to consider small rewards
        unclaimedAmount = (perShareUnclaimedAmount * 1e18) / userStakingTokenTotal;
        unclaimedAmount = unclaimedAmount / 1e18;

        // If reward less than 0 – apply min reward
        if (unclaimedAmount == 0) unclaimedAmount = MIN_REWARD;

        if (feeConfig.feePercentage > 0) {
            uint256 currentFee = _calculateFee(unclaimedAmount, feeConfig.feePercentage);
            unclaimedAmount -= currentFee;
        }
    }

    /**
     * @dev Returns the amount of locked shares.
     *
     * @param account The user address.
     * @return The amount of locked shares.
     */
    function lockedOf(address account) public view returns (uint256) {
        return _userContribution[account].totalLocked - _userContribution[account].totalReleased - unlockedOf(account);
    }

    /**
     * @dev Returns the amount of unlocked shares.
     *
     * @param account The user address.
     * @return The amount of unlocked shares.
     */
    function unlockedOf(address account) public view returns (uint256) {
        return _unlocked(account);
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
     * @dev Returns the max possible amount of shares to redeem.
     */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return unlockedOf(owner);
    }

    /**
     * @dev Returns the max possible amount of assets to withdraw.
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256 assets) {
        return convertToAssets(unlockedOf(owner));
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
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC165) returns (bool) {
        return interfaceId == type(IERC7540).interfaceId || super.supportsInterface(interfaceId);
    }
}
