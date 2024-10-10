// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { DLT } from "./DLT.sol";
import { DLTEnumerableWithHTS } from "./extensions/DLTEnumerableWithHTS.sol";
import { HTSNonFungibleToken } from "./extensions/HTSNonFungibleToken.sol";
import { DLTPermit } from "./extensions/DLTPermit.sol";

contract TestDLTWithHTS is DLT, DLTEnumerableWithHTS, DLTPermit {
    constructor(
        string memory name,
        string memory symbol,
        string memory version
    ) payable DLT(name, symbol) DLTPermit(name, version) HTSNonFungibleToken(name, symbol) {}

    function mintMainAsset(address account, uint256 amount) payable external {
        _mintMain(account, amount);
    }

    function mintSubAsset(address account, int64 mainId, int64 subId, uint256 amount) external {
        _mint(account, mainId, subId, amount);
    }

    function burn(address account, int64 mainId, int64 subId, uint256 amount) external {
        _burn(account, mainId, subId, amount);
    }

    function transfer(address sender, address recipient, int64 mainId, int64 subId, uint256 amount) external {
        _transfer(sender, recipient, mainId, subId, amount);
    }

    function allow(address sender, address recipient, int64 mainId, int64 subId, uint256 amount) external {
        _approve(sender, recipient, mainId, subId, amount);
    }

    function _mint(
        address recipient,
        int64 mainId,
        int64 subId,
        uint256 amount
    ) internal virtual override(DLT, DLTEnumerableWithHTS) {
        super._mint(recipient, mainId, subId, amount);
    }

    function _burn(
        address recipient,
        int64 mainId,
        int64 subId,
        uint256 amount
    ) internal virtual override(DLT, DLTEnumerableWithHTS) {
        super._burn(recipient, mainId, subId, amount);
    }
}
