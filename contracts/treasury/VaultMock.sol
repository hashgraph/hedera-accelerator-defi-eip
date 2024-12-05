// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VaultMock {
    using SafeERC20 for IERC20;

    IERC20 public usdc;
    uint256 public totalDeposits;

    constructor(address _usdcAddress) {
        usdc = IERC20(_usdcAddress);
    }

    function deposit(uint256 amount) external {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposits += amount;
    }
}
