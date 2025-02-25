// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract BuildingGovernanceStorage {
    /// @custom:storage-location erc7201:hashgraph.buildings.BuildingGovernance
    struct BuildingGovernanceData {
        address treasury;
    }

    //keccak256(abi.encode(uint256(keccak256("hashgraph.buildings.BuildingGovernance")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BuildingGovernanceStorageLocation = 0x72a4ccd47996c0aa9e54efd606e03b13bee57794bd0974b6dda8fcd457f37700;

    function _getBuildingGovernanceStorage() internal pure returns (BuildingGovernanceData storage $) {
        assembly {
            $.slot := BuildingGovernanceStorageLocation
        }
    }    
    
    enum ProposalLevel { GovernorVote }
    enum ProposalType { Text, Payment }
    event ProposalCreated(ProposalType proposalType, uint256 id, address proposer);
}
