// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title Token Balancer
 */
interface ITokenBalancer {
    /**
     * @notice CreatedToken event.
     * @dev Emitted after contract initialization, when token was deployed.
     *
     * @param createdToken The address of the token.
     */
    event CreatedToken(address indexed createdToken);
    /**
     * @notice Deposit event.
     * @dev Emitted after the deposit.
     *
     * @param token The address of the deposited token.
     * @param sender The address of the account that performed the deposit.
     * @param amount The amount of assets that were deposited.
     */
    event Deposit(address indexed token, address indexed sender, uint256 amount);
    /**
     * @notice Withdraw event.
     * @dev Emitted after the withdraw.
     *
     * @param token The address of the deposited token.
     * @param receiver The address that received the S token after the deposit.
     * @param amount The amount of assets that were deposited.
     */
    event Withdraw(address indexed token, address indexed receiver, uint256 amount);
    event TokenAdded(address indexed token, bytes32 priceId, uint256 allocationPercentage);
    event TargetAllocationPercentageChanged(address indexed token, uint256 allocationPercentage);

    struct TokenInfo {
        address aToken;
        address token;
        bytes32 priceId;
        uint256 targetPercentage;
        bool isAutoCompounder;
    }

    /**
     * @dev Add token to the system.
     *
     * @param aToken The A/V token address.
     * @param priceId The price ID in terms of Pyth oracle.
     * @param percentage The target allocation percentage.
     * @param isAutoCompounder The bool flag true if the token is AutoCompaunder.
     */
    function addTrackingToken(address aToken, bytes32 priceId, uint256 percentage, bool isAutoCompounder) external;
}
