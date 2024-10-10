// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IERC7540 {
    /**
     * @notice Deposit Requested event.
     * @dev Emitted when a user requests deposit.
     *
     * @param controller The controller address.
     * @param owner The owner address.
     * @param requestId The request ID.
     * @param sender The sender address.
     * @param assets The assets amount.
     */
    event DepositRequested(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 assets
    );

    /**
     * @notice Redeem Requested event.
     * @dev Emitted when a user requests redeem.
     *
     * @param controller The controller address.
     * @param owner The owner address.
     * @param requestId The request ID.
     * @param sender The sender address.
     * @param shares The shares amount.
     */
    event RedeemRequested(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 shares
    );

    function requestDeposit(uint256 assets, address receiver, address owner) external;

    function pendingDepositRequest(address owner, uint256 requestId) external view returns (uint256 assets);

    function requestRedeem(uint256 shares, address operator, address owner) external;

    function pendingRedeemRequest(address owner, uint256 requestId) external view returns (uint256 shares);
}
