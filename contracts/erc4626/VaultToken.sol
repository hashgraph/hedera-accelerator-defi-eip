// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import {ERC20} from "./ERC20.sol";

contract VaultToken is ERC20 {
    constructor(uint8 decimals) ERC20("VaultToken", "VLT", decimals) {
        _mint(msg.sender, 500000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        require(amount != 0, "Zero token amount");
        require(to != address(0), "Zero to address");

        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        require(amount != 0, "Zero token amount");
        require(from != address(0), "Zero from address");

        _burn(from, amount);
    }
}
