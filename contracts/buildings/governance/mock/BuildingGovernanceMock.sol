// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {BuildingGovernance} from '../BuildingGovernance.sol';

contract BuildingGovernanceMock is BuildingGovernance {
    function version() public override pure returns (string memory) {
        return '2.0';
    }
}
