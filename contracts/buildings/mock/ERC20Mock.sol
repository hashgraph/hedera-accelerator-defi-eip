// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    uint8 private customDecimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol)
    {
        customDecimals = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return customDecimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
