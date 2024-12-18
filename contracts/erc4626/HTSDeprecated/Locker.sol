// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "../../common/IERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IHRC} from "../../common/hedera/IHRC.sol";
import "../../common/safe-HTS/SafeHTS.sol";
import "../../common/safe-HTS/IHederaTokenService.sol";

/**
 * @title Locker
 *
 * The contract which allows to stake single ERC20/HTS token and claim a reward tokens
 * according to the configured locking period.
 */
contract Locker is Ownable {
    using SafeCast for uint;

    /**
     * @notice Staked event.
     * @dev Emitted when user stakes an asset.
     *
     * @param user The user address.
     * @param token The staking token address.
     * @param amount The amount to stake.
     */
    event Staked(address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Reward added event.
     * @dev Emitted when owner adds an asset.
     *
     * @param token The added token address.
     * @param amount The added amount.
     */
    event RewardAdded(address indexed token, uint256 amount);

    /**
     * @notice Withdraw event.
     * @dev Emitted when user withdraws an asset.
     *
     * @param user The user address.
     * @param token The token address.
     * @param amount The amount to withdraw.
     */
    event Withdraw(address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Claim event.
     * @dev Emitted when user claims reward.
     *
     * @param user The user address.
     * @param token The claimed token.
     * @param amount The claimed amount.
     */
    event Claim(address indexed user, address indexed token, uint256 amount);

    // Throws if a token is not added by the owner
    error TokenNotSupported(address _token);

    // Throws if a user tries to unlock the staked amount before reaching lock period
    error LockPeriodNotReached(uint256 lockPeriodReachedAt);

    // The max number of supported reward tokens
    uint8 internal constant MAX_SUPPORTED_TOKENS_NUMBER = 20;

    // Staking token
    address internal stakingToken;

    // Lock Duration
    uint64 internal lockPeriod;

    // Total staked
    uint256 internal totalStaked;

    // Reward tokens
    address[] internal rewardTokens;

    // UserInfo Struct
    struct UserInfo {
        uint256 shares;
        mapping(address => uint256) lastClaimedAmount;
        uint256 lockTimeStart;
    }

    // RewardsInfo struct
    struct RewardsInfo {
        uint256 amount;
        bool exist;
    }

    // User address => User Info
    mapping(address => UserInfo) internal userContribution;

    // Reward token address => Rewards Info
    mapping(address => RewardsInfo) internal rewardsInfoByToken;

    /**
     * @dev Initializes the contract with the required parameters.
     *
     * @param _stakingToken The staking token address.
     * @param _rewardTokens The reward tokens.
     * @param _lockPeriod The initial lock period.
     */
    constructor(
        address _stakingToken,
        address[] memory _rewardTokens,
        uint256 _lockPeriod
    ) payable Ownable(msg.sender) {
        require(_stakingToken != address(0), "Locker: staking token cannot be zero address");
        require(_lockPeriod != 0, "Locker: too short lock period");
        require(
            _rewardTokens.length > 0 && _rewardTokens.length <= MAX_SUPPORTED_TOKENS_NUMBER,
            "Locker: incorrect number of tokens"
        );

        stakingToken = _stakingToken;
        lockPeriod = _lockPeriod.toUint64();
        rewardTokens = _rewardTokens;

        uint256 tokensSize = _rewardTokens.length;
        for (uint256 i = 0; i < tokensSize; i++) {
            SafeHTS.safeAssociateToken(_rewardTokens[i], address(this));
        }

        SafeHTS.safeAssociateToken(_stakingToken, address(this));
    }

    /**
     * @dev Stakes the amount of the staking token to the contract.
     *
     * @param _amount The amount of the staking token.
     */
    function stake(uint256 _amount) external {
        require(_amount != 0, "Locker: invalid amount");

        if (userContribution[msg.sender].lockTimeStart == 0) {
            uint256 rewardsSize = rewardTokens.length;

            for (uint256 i = 0; i < rewardsSize; i++) {
                userContribution[msg.sender].lastClaimedAmount[rewardTokens[i]] = rewardsInfoByToken[rewardTokens[i]]
                    .amount;
            }

            userContribution[msg.sender].shares = _amount;
            userContribution[msg.sender].lockTimeStart = block.timestamp;
            totalStaked += _amount;

            SafeHTS.safeTransferToken(stakingToken, msg.sender, address(this), int64(uint64(_amount)));

            emit Staked(msg.sender, stakingToken, _amount);
        } else {
            userContribution[msg.sender].shares += _amount;
            userContribution[msg.sender].lockTimeStart = block.timestamp;
            totalStaked += _amount;

            claimAllReward();
            SafeHTS.safeTransferToken(stakingToken, msg.sender, address(this), int64(uint64(_amount)));

            emit Staked(msg.sender, stakingToken, _amount);
        }
    }

    /**
     * @dev Adds the amount of the reward token to the contract.
     *
     * @param _token The reward token address.
     * @param _amount The amount to add.
     */
    function addReward(address _token, uint256 _amount) external onlyOwner {
        require(_token != address(0), "Locker: invalid token address");
        require(_amount != 0, "Locker: invalid amount");
        require(totalStaked != 0, "Locker: no staked token");

        uint256 perShareRewards;
        perShareRewards = _amount / totalStaked;

        if (!rewardsInfoByToken[_token].exist) {
            rewardTokens.push(_token);
            rewardsInfoByToken[_token].exist = true;
            rewardsInfoByToken[_token].amount = perShareRewards;
            SafeHTS.safeTransferToken(_token, owner(), address(this), int64(uint64(_amount)));

            emit RewardAdded(_token, _amount);
        } else {
            rewardsInfoByToken[_token].amount += perShareRewards;
            SafeHTS.safeTransferToken(_token, owner(), address(this), int64(uint64(_amount)));

            emit RewardAdded(_token, _amount);
        }
    }

    /**
     * @dev Withdraws the staking token and automatically claims rewards.
     *
     * @param _rewardsToClaim The tokens to claim.
     * @param _amount The amount to withdraw.
     */
    function _withdraw(address[] calldata _rewardsToClaim, uint256 _amount) internal {
        claimSpecificsReward(_rewardsToClaim);

        SafeHTS.safeTransferToken(address(stakingToken), address(this), msg.sender, int64(uint64(_amount)));

        userContribution[msg.sender].shares -= _amount;
        totalStaked -= _amount;

        emit Withdraw(msg.sender, address(stakingToken), _amount);
    }

    /**
     * @dev Unlocks the staked tokens if lock period passed and claims specified rewards.
     *
     * @param _rewardsToClaim The tokens to claim.
     * @param _amount The amount to unlock.
     */
    function unlock(address[] calldata _rewardsToClaim, uint256 _amount) external {
        require(_amount != 0, "Locker: invalid amount");
        require(_rewardsToClaim.length != 0, "Locker: invalid amount");

        uint256 lockPeriodReachedAt = userContribution[msg.sender].lockTimeStart + lockPeriod;

        if (lockPeriodReachedAt < block.timestamp) {
            _withdraw(_rewardsToClaim, _amount);
        } else {
            revert LockPeriodNotReached(lockPeriodReachedAt);
        }
    }

    /**
     * @dev Claims all rewards.
     */
    function claimAllReward() public {
        uint256 rewardsSize = rewardTokens.length;

        uint256 reward;
        address token;

        for (uint256 i = 0; i < rewardsSize; i++) {
            token = rewardTokens[i];

            if (!_isTokenExist(token)) revert TokenNotSupported(token);

            reward = calculateReward(token);

            userContribution[msg.sender].lastClaimedAmount[token] = rewardsInfoByToken[token].amount;
            SafeHTS.safeTransferToken(token, address(this), msg.sender, int64(uint64(reward)));

            emit Claim(msg.sender, token, reward);
        }
    }

    /**
     * @dev Returns the locked amount for the caller.
     */
    function getLockedAmount() external view returns (uint256) {
        return userContribution[msg.sender].shares;
    }

    /**
     * @dev Returns the total staked amount.
     */
    function getTVL() external view returns (uint256) {
        return totalStaked;
    }

    /**
     * @dev Returns the lock period.
     */
    function getLockPeriod() external view returns (uint256) {
        return lockPeriod;
    }

    /**
     * @dev Returns the staking token address.
     */
    function getStakingToken() external view returns (address) {
        return stakingToken;
    }

    /**
     * @dev Returns the reward tokens.
     */
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /**
     * @dev Checks token support.
     *
     * @param _token The token address.
     * @return exist The existance flag.
     */
    function _isTokenExist(address _token) private view returns (bool exist) {
        return rewardsInfoByToken[_token].exist;
    }

    /**
     * @dev Calculates reward for specified token.
     *
     * @param _token The token address.
     * @return exist The calculated reward.
     */
    function calculateReward(address _token) public view returns (uint256) {
        return
            (rewardsInfoByToken[_token].amount - userContribution[msg.sender].lastClaimedAmount[_token]) *
            userContribution[msg.sender].shares;
    }

    /**
     * @dev Claims specified rewards.
     *
     * @param _tokensToClaim The tokens to claim.
     */
    function claimSpecificsReward(address[] calldata _tokensToClaim) public {
        uint256 tokensToClaimSize = _tokensToClaim.length;

        uint256 reward;
        address token;

        for (uint256 i = 0; i < tokensToClaimSize; i++) {
            token = _tokensToClaim[i];

            if (!_isTokenExist(token)) revert TokenNotSupported(token);

            reward = calculateReward(token);

            userContribution[msg.sender].lastClaimedAmount[token] = rewardsInfoByToken[token].amount;
            SafeHTS.safeTransferToken(token, address(this), msg.sender, int64(uint64(reward)));

            emit Claim(msg.sender, token, reward);
        }
    }
}
