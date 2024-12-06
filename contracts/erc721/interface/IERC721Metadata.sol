// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Metadata is IERC721 {
    function mint(address, string memory) external;
}
