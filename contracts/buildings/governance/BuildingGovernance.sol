// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {BuildingGovernor} from "./BuildingGovernor.sol";
import {BuildingGovernanceStorage} from "./BuildingGovernanceStorage.sol";

contract BuildingGovernance is BuildingGovernor, BuildingGovernanceStorage {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address token, string memory name, address initialOwner, address treasury) public initializer {
        __BuildingGovernor_init(IVotes(token), name, initialOwner);
        
        BuildingGovernanceData storage $ = _getBuildingGovernanceStorage();
        $.treasury = treasury;
    }

    function createTextProposal(ProposalLevel level, string memory description) public returns(uint256 proposalId) {
        // TODO: decide between multisig vote proposal or governor proposal giving the level
        // Multisig
        // GovernorVote
        
        // Empty arrays mean no executable actions are attached.
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(0);
        values[0] = 0 ether;
        calldatas[0] = new bytes(0x0);

        proposalId = propose(targets, values, calldatas, description);

        emit ProposalCreated(ProposalType.Text, proposalId, msg.sender);
    }

    function createPaymentProposal(address token, uint256 amount, address to, string memory description) public returns (uint256 proposalId) {
        BuildingGovernanceData storage $ = _getBuildingGovernanceStorage();
        // keep track of payments made in a month
        // decide between multisig vote proposal or governor proposal 

        address[] memory _token = new address[](1);
        _token[0] = token;

        uint256[] memory _values = new uint256[](1);
        _values[0] = 0;

        bytes[] memory _calldata = new bytes[](1);
        _calldata[0] = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            $.treasury,
            to,
            amount
        );

        proposalId = propose(_token, _values, _calldata, description);
        
        emit ProposalCreated(ProposalType.Payment, proposalId, msg.sender);
    }
}
