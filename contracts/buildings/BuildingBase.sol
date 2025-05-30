// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {CallContract} from "./library/CallContract.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract BuildingBase is IERC721Receiver, Initializable, OwnableUpgradeable {

    /**
     * Proxy Contract initialized
     */
    function __Building_init (address initialOwner) internal onlyInitializing {
        __Ownable_init(initialOwner);
    }

    /**
     * callContract Calls any contract and pass the message mantaining msg.sender and msg.value
     * @param callableContract address of the contract to be called
     * @param data bytes to be passed to the called contract
     */
    function callContract(address callableContract, bytes memory data) external payable onlyOwner returns(bytes memory) {
        return CallContract.call(callableContract, data);
    }

    /**
     * mandatory method in orther to receive ERC721 safe transfers.
     */
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
