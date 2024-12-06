// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

library CallContract {
    function call(address callableContract, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory result) = callableContract.call{ value: msg.value }(data);
        require(success, "Building: call failed");
        return result;
    }
}
