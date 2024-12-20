// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ExampleERC20 is ERC20 {
    uint8 _decimals = 18;

    constructor(uint256 initialSupply, string memory name, string memory symbol, uint8 _dec) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply * (10 ** 18));

        _decimals = _dec;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
