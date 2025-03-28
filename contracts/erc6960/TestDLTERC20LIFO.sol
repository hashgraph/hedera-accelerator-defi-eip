// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { DLT } from "./DLT.sol";
import { DLTERC20LIFO } from "./extensions/DLTERC20LIFO.sol";

contract TestDLTERC20LIFO is DLTERC20LIFO {
    constructor(
        string memory name,
        string memory symbol
    ) DLT(name, symbol) {}

    function mint(address account, int64 mainId, int64 subId, uint256 amount) external {
        _safeMint(account, mainId, subId, amount);
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

}
