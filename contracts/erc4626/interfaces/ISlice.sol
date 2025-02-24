// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title Slice
 */
interface ISlice {
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
     * @param token The address of the withdrawn token.
     * @param receiver The address that received the withdrawn token.
     * @param amount The amount of assets that were withdrawn.
     */
    event Withdraw(address indexed token, address indexed receiver, uint256 amount);
    /**
     * @notice AllocationAdded event.
     * @dev Emitted after the adding new allocation.
     *
     * @param token The address of the added token.
     * @param asset The address of the underlying asset.
     * @param priceFeed The address of the AggregatorV3 contract.
     * @param allocationPercentage The allocation percentage to maintain.
     */
    event AllocationAdded(
        address indexed token,
        address indexed asset,
        address indexed priceFeed,
        uint16 allocationPercentage
    );
    /**
     * @notice AllocationPercentageChanged event.
     * @dev Emitted after the changing allocation percentage.
     *
     * @param token The address of the token.
     * @param allocationPercentage The new allocation percentage to maintain.
     */
    event AllocationPercentageChanged(address indexed token, uint16 allocationPercentage);

    // Allocation struct
    struct Allocation {
        address aToken; // aToken address
        address asset; // Underlying asset
        uint16 targetPercentage; // Target percentage (e.g., 3000 for 30%)
    }

    /**
     * @dev Makes set of swaps to reach target balances of aTokens from generated payloads.
     */
    function rebalance() external;

    /**
     * @dev Deposits to the AutoCompounder contract.
     *
     * @param aToken The address of the AutoCompounder.
     * @param amount The aToken amount to deposit.
     * @return aTokenAmount The amount of deposited aToken and minted sToken.
     */
    function deposit(address aToken, uint256 amount) external returns (uint256 aTokenAmount);

    /**
     * @dev Withdraws set of stored tokens.
     *
     * @param sTokenAmount The sToken amount to withdraw.
     * @return amounts The array of withdrawn aToken amounts.
     */
    function withdraw(uint256 sTokenAmount) external returns (uint256[] memory amounts);

    /**
     * @dev Add token to the system.
     *
     * @param aToken The aToken address.
     * @param priceFeed The address of the AggregatorV3 contract.
     * @param percentage The target allocation percentage.
     */
    function addAllocation(address aToken, address priceFeed, uint16 percentage) external;

    /**
     * @dev Sets new aToken allocation percentage.
     *
     * @param aToken The aToken address.
     * @param percentage The new allocation percentage to maintain.
     */
    function setAllocationPercentage(address aToken, uint16 percentage) external;

    /**
     * @dev Returns token allocation for the passed aToken address.
     *
     * @param aToken The aToken address.
     */
    function getTokenAllocation(address aToken) external view returns (Allocation memory);
}
