// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BuildingToken} from "./library/BuildingToken.sol";
import {CallContract} from "./library/CallContract.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract BuildingBase is IERC721Receiver, Initializable, OwnableUpgradeable {

    function __Building_init () internal onlyInitializing {
        __Ownable_init(_msgSender());
    }

    function callContract(address callableContract, bytes memory data) external payable onlyOwner returns(bytes memory) {
        return CallContract.call(callableContract, data);
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
