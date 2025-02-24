// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IRewards
 */
interface IRewards {
    /**
     * @dev Returns rewards for a user with fee considering.
     *
     * @param _user The user address.
     * @param _rewardToken The reward address.
     * @return unclaimedAmount The calculated rewards.
     */
    function getUserReward(address _user, address _rewardToken) external view returns (uint256);

    /**
     * @dev Claims all pending reward tokens for the caller.
     *
     * @param _startPosition The starting index in the reward token list from which to begin claiming rewards.
     * @return The index of the start position after the last claimed reward and the total number of reward tokens.
     */
    function claimAllReward(uint256 _startPosition, address receiver) external returns (uint256, uint256);
}
