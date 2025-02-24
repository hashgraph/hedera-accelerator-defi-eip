// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Slice} from "../../contracts/erc4626/Slice.sol";

import {AutoCompounder} from "../../contracts/erc4626/AutoCompounder.sol";
import {BasicVault} from "../../contracts/erc4626/BasicVault.sol";

import {VaultToken} from "../../contracts/erc4626/VaultToken.sol";

import {FeeConfiguration} from "../../contracts/common/FeeConfiguration.sol";

import {IUniswapV2Router02} from "../../contracts/erc4626/interfaces/IUniswapV2Router02.sol";

contract SliceTest is Test {
    string internal constant metadataURI = "ipfs://bafybeibnsoufr2renqzsh347nrx54wcubt5lgkeivez63xvivplfwhtpym/m";

    address internal owner = 0xf5d7D351A5511a13de1f73d4882f88032A490a27;

    address internal uniswapRouter = 0x815Bf1AD6d2B1c0E393C033227df0a88C48f83Be;
    address internal priceFeed = 0x269501f5674BeE3E8fef90669d3faa17021344d0;

    Slice slice;

    AutoCompounder aToken1;
    AutoCompounder aToken2;

    BasicVault vToken1;
    BasicVault vToken2;

    VaultToken underlying1;
    VaultToken underlying2;

    VaultToken rewardToken;

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_URL");
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);

        vm.prank(owner);
        underlying1 = new VaultToken();
        vm.prank(owner);
        underlying2 = new VaultToken();

        vm.prank(owner);
        rewardToken = new VaultToken();

        FeeConfiguration.FeeConfig memory zeroFeeConfig = FeeConfiguration.FeeConfig({
            receiver: address(0),
            token: address(0),
            feePercentage: 0
        });

        vm.prank(owner);
        vToken1 = new BasicVault(IERC20(address(underlying1)), "TST", "TST", zeroFeeConfig, owner, owner);
        vm.prank(owner);
        vToken2 = new BasicVault(IERC20(address(underlying2)), "TST", "TST", zeroFeeConfig, owner, owner);

        vm.prank(owner);
        aToken1 = new AutoCompounder(uniswapRouter, address(vToken1), address(rewardToken), "TST", "TST");
        vm.prank(owner);
        aToken2 = new AutoCompounder(uniswapRouter, address(vToken2), address(rewardToken), "TST", "TST");

        vm.prank(owner);
        slice = new Slice(uniswapRouter, address(rewardToken), "sToken", "sToken", metadataURI);
    }

    function testRebalance() public {
        uint256 amountToDeposit = 50_000_000_000_000;
        uint256 rewardAmount = 50000000_000_000_000_000_000_000;

        vm.prank(owner);
        rewardToken.approve(uniswapRouter, rewardAmount);
        vm.prank(owner);
        underlying1.approve(uniswapRouter, rewardAmount);
        vm.prank(owner);
        underlying2.approve(uniswapRouter, rewardAmount);

        deal(address(underlying1), owner, 50000000_000_000_000_000_000_0000);
        deal(address(underlying2), owner, 50000000_000_000_000_000_000_0000);
        deal(address(rewardToken), owner, 50000000_000_000_000_000_000_00000);

        // Create LPs
        vm.prank(owner);
        IUniswapV2Router02(uniswapRouter).addLiquidity(
            address(rewardToken),
            address(underlying1),
            5000000_000_000_000_000_000_000,
            5000000_000_000_000_000_000_000,
            0,
            0,
            owner,
            type(uint256).max
        );
        vm.prank(owner);
        IUniswapV2Router02(uniswapRouter).addLiquidity(
            address(rewardToken),
            address(underlying2),
            5000000_000_000_000_000_000,
            5000000_000_000_000_000_000,
            0,
            0,
            owner,
            type(uint256).max
        );

        vm.prank(owner);
        underlying1.approve(address(slice), amountToDeposit);
        vm.prank(owner);
        underlying2.approve(address(slice), amountToDeposit);

        uint16 allocationPercentage1 = 4000;
        uint16 allocationPercentage2 = 6000;

        // Add allocation percentages
        vm.prank(owner);
        slice.addAllocation(address(aToken1), priceFeed, allocationPercentage1);
        vm.prank(owner);
        slice.addAllocation(address(aToken2), priceFeed, allocationPercentage2);

        // Deposit to Autocompounders
        vm.prank(owner);
        slice.deposit(address(aToken1), amountToDeposit);
        vm.prank(owner);
        slice.deposit(address(aToken2), amountToDeposit);

        // Add allowance for adding rewards
        vm.prank(owner);
        rewardToken.approve(address(vToken1), rewardAmount);
        vm.prank(owner);
        rewardToken.approve(address(vToken2), rewardAmount);

        // Add rewards to Vaults
        vm.prank(owner);
        vToken1.addReward(address(rewardToken), rewardAmount);
        vm.prank(owner);
        vToken2.addReward(address(rewardToken), rewardAmount);

        console.log("aToken1 balance before: ", aToken1.balanceOf(address(slice)));
        console.log("aToken2 balance before: ", aToken2.balanceOf(address(slice)));
        console.log("reward token balance before: ", rewardToken.balanceOf(address(slice)));

        vm.prank(owner);
        slice.rebalance();

        console.log("aToken1 balance after: ", aToken1.balanceOf(address(slice)));
        console.log("aToken2 balance after: ", aToken2.balanceOf(address(slice)));
        console.log("reward token balance after: ", rewardToken.balanceOf(address(slice)));
    }
}
