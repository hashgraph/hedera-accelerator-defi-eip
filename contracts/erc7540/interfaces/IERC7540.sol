// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

/**
 * @title IERC7540
 * @author Hashgraph
 */
interface IERC7540 {
    /**
     * @notice Deposit Requested event.
     * @dev Emitted when a user requests deposit.
     *
     * @param controller The controller address.
     * @param owner The owner address.
     * @param sender The sender address.
     * @param assets The assets amount.
     */
    event DepositRequested(address indexed controller, address indexed owner, address sender, uint256 assets);

    /**
     * @notice Redeem Requested event.
     * @dev Emitted when a user requests redeem.
     *
     * @param controller The controller address.
     * @param owner The owner address.
     * @param sender The sender address.
     * @param shares The shares amount.
     */
    event RedeemRequested(address indexed controller, address indexed owner, address sender, uint256 shares);

    /**
     * @notice The error is emitted when a user try to make a new deposit request
     * and the deposited amount is grater than deposit limit.
     */
    error MaxDepositRequestExceeded(address controller, uint256 assets, uint256 maxDeposit);

    /**
     * @notice The error is emitted when a user try to make a new redeem request
     * but there is lack of shares.
     */
    error MaxRedeemRequestExceeded(address controller, uint256 shares, uint256 maxShares);

    /**
     * @dev Creates a new pending async deposit request.
     *
     * @param assets The amount of assets to deposit.
     * @param controller The controller address.
     * @param owner The owner address.
     */
    function requestDeposit(uint256 assets, address controller, address owner) external;

    /**
     * @dev Creates a new pending async redeem request.
     *
     * @param shares The amount of shares to redeem.
     * @param controller The controller address.
     * @param owner The owner address.
     */
    function requestRedeem(uint256 shares, address controller, address owner) external;

    /**
     * @dev Returns the pending asset amount from the deposit request.
     *
     * @param owner The owner of the request.
     * @return assets The assets amount.
     */
    function pendingDepositRequest(address owner) external view returns (uint256 assets);

    /**
     * @dev Returns the pending asset amount from the redeem request.
     *
     * @param owner The owner of the request.
     * @return shares The shares amount.
     */
    function pendingRedeemRequest(address owner) external view returns (uint256 shares);

    /**
     * @dev Sets or removes an operator for the caller.
     *
     * @param operator The address of the operator.
     * @param approved The approval status.
     * @return success Whether the call was executed successfully or not
     */
    function setOperator(address operator, bool approved) external returns (bool success);
}
