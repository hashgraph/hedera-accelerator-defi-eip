// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IDLTReceiver } from "../interfaces/IDLTReceiver.sol";

contract DLTReceiverRevertable is IDLTReceiver {
    constructor() {}

    function onDLTReceived(
        address operator,
        address from,
        int64 mainId,
        int64 subId,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes4) {
        revert("DLTReceiverRevertable");
    }

    function onDLTBatchReceived(
        address,
        address,
        int64[] memory,
        int64[] memory,
        uint256[] memory,
        bytes calldata data
    ) external returns (bytes4) {
        revert("DLTReceiverRevertable");
    }
}
