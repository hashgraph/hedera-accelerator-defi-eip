import { ethers, expect } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";
import { ZeroAddress, ZeroHash } from "ethers";
import { VaultToken, Slice, BasicVault, AutoCompounder } from "../../typechain-types";

import {
    usdcAddress,
    uniswapRouterAddress,
    chainlinkAggregatorMockAddress
} from "../../constants";

// constants
const sTokenPayload = "sToken";
const metadataUri = "ipfs://bafybeibnsoufr2renqzsh347nrx54wcubt5lgkeivez63xvivplfwhtpym/m";

// Zero fee
const feeConfig = {
    receiver: ZeroAddress,
    token: ZeroAddress,
    feePercentage: 0,
};

// Tests
describe("Slice", function () {
    async function deployFixture() {
        const [
            owner,
        ] = await ethers.getSigners();

        let client = Client.forTestnet();

        const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
        const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

        client.setOperator(
            operatorAccountId,
            operatorPrKey
        );

        // Staking Token
        const VaultToken = await ethers.getContractFactory("VaultToken");

        const stakingToken1 = await VaultToken.deploy(
        ) as VaultToken;
        await stakingToken1.waitForDeployment();

        const stakingToken2 = await VaultToken.deploy(
        ) as VaultToken;
        await stakingToken2.waitForDeployment();

        // Reward Token
        const rewardToken = await VaultToken.deploy(
        ) as VaultToken;
        await rewardToken.waitForDeployment();

        // Basic Vault
        const Vault = await ethers.getContractFactory("BasicVault");

        const vault1 = await Vault.deploy(
            stakingToken1.target,
            "TST",
            "TST",
            feeConfig,
            owner.address,
            owner.address
        ) as BasicVault;
        await vault1.waitForDeployment();

        const vault2 = await Vault.deploy(
            stakingToken2.target,
            "TST",
            "TST",
            feeConfig,
            owner.address,
            owner.address
        ) as BasicVault;
        await vault2.waitForDeployment();

        // AutoCompounder
        const AutoCompounder = await ethers.getContractFactory("AutoCompounder");

        const autoCompounder1 = await AutoCompounder.deploy(
            uniswapRouterAddress,
            vault1.target,
            rewardToken.target,
            "TST",
            "TST"
        ) as AutoCompounder;
        await autoCompounder1.waitForDeployment();

        const autoCompounder2 = await AutoCompounder.deploy(
            uniswapRouterAddress,
            vault2.target,
            rewardToken.target,
            "TST",
            "TST"
        ) as AutoCompounder;
        await autoCompounder2.waitForDeployment();

        // await stakingToken.mint(testAccount.address, ethers.parseUnits("500000000", 18));

        // Slice
        const Slice = await ethers.getContractFactory("Slice");
        const slice = await Slice.deploy(
            uniswapRouterAddress,   // Uniswap router V2
            rewardToken.target,     // BaseToken TODO: Change to real USDC
            sTokenPayload,          // sToken name
            sTokenPayload,          // sToken symbol
            metadataUri,            // Slice metadata URI
        ) as Slice;
        await slice.waitForDeployment();

        return {
            slice,
            vault1,
            vault2,
            autoCompounder1,
            autoCompounder2,
            stakingToken1,
            stakingToken2,
            rewardToken,
            client,
            owner,
        };
    }

    describe("rebalance", function () {
        it.only("Should distribute tokens close to the provided allocation Autocompounders", async function () {
            const {
                slice,
                owner,
                vault1,
                vault2,
                autoCompounder1,
                autoCompounder2,
                stakingToken1,
                stakingToken2,
                rewardToken,
            } = await deployFixture();
            const allocationPercentage1 = 4000;
            const allocationPercentage2 = 6000;
            const amountToDeposit = ethers.parseUnits("50", 12);
            const rewardAmount = ethers.parseUnits("50000000", 18);

            const uniswapV2Router02 = await ethers.getContractAt("contracts/erc4626/interfaces/IUniswapV2Router02.sol:IUniswapV2Router02", uniswapRouterAddress);

            // Add Liquidity
            await rewardToken.approve(uniswapRouterAddress, ethers.parseUnits("50000000", 18));
            await stakingToken1.approve(uniswapRouterAddress, ethers.parseUnits("50000000", 18));
            await stakingToken2.approve(uniswapRouterAddress, ethers.parseUnits("50000000", 18));

            const addLiquidityTx1 = await uniswapV2Router02.addLiquidity(
                rewardToken.target,
                stakingToken1.target,
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                owner.address,
                ethers.MaxUint256,
                { from: owner.address, gasLimit: 3000000 }
            );

            const addLiquidityTx2 = await uniswapV2Router02.addLiquidity(
                rewardToken.target,
                stakingToken2.target,
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                owner.address,
                ethers.MaxUint256,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log("Add Liquidity Tx1: ", addLiquidityTx1.hash);
            console.log("Add Liquidity Tx2: ", addLiquidityTx2.hash);

            // Add tracking tokens
            await slice.addAllocation(
                autoCompounder1.target,
                chainlinkAggregatorMockAddress,
                allocationPercentage1
            );
            await slice.addAllocation(
                autoCompounder2.target,
                chainlinkAggregatorMockAddress,
                allocationPercentage2
            );

            console.log("Tracking tokens added");

            // Deposit to Slice
            await stakingToken1.approve(slice.target, amountToDeposit);
            await stakingToken2.approve(slice.target, amountToDeposit);

            const depositAutoCompounderTx1 = await slice.deposit(autoCompounder1.target, amountToDeposit);
            console.log("Deposit to AutoCompounder Tx1: ", depositAutoCompounderTx1.hash);
            const depositAutoCompounderTx2 = await slice.deposit(autoCompounder2.target, amountToDeposit);
            console.log("Deposit to AutoCompounder Tx2: ", depositAutoCompounderTx2.hash);

            // Add reward
            await rewardToken.approve(vault1.target, rewardAmount);
            await rewardToken.approve(vault2.target, rewardAmount);

            const addRewardTx1 = await vault1.addReward(rewardToken.target, rewardAmount);
            const addRewardTx2 = await vault2.addReward(rewardToken.target, rewardAmount);
            console.log(addRewardTx1.hash);
            console.log(addRewardTx2.hash);

            console.log("aToken1 balance before: ", await autoCompounder1.balanceOf(slice.target));
            console.log("aToken2 balance before: ", await autoCompounder2.balanceOf(slice.target));
            console.log("vToken1 balance before: ", await vault1.balanceOf(slice.target));
            console.log("vToken2 balance before: ", await vault2.balanceOf(slice.target));
            console.log("USDC balance before: ", await rewardToken.balanceOf(slice.target));
            console.log("Underlying1 balance before: ", await stakingToken1.balanceOf(slice.target));
            console.log("Underlying2 balance before: ", await stakingToken2.balanceOf(slice.target));

            const tx = await slice.rebalance();

            console.log(`Rebalance tx: ${tx.hash}`);

            console.log("aToken1 balance after: ", await autoCompounder1.balanceOf(slice.target));
            console.log("aToken2 balance after: ", await autoCompounder2.balanceOf(slice.target));
            console.log("vToken1 balance after: ", await vault1.balanceOf(slice.target));
            console.log("vToken2 balance after: ", await vault2.balanceOf(slice.target));
            console.log("USDC balance after: ", await rewardToken.balanceOf(slice.target));
            console.log("Underlying1 balance after: ", await stakingToken1.balanceOf(slice.target));
            console.log("Underlying2 balance after: ", await stakingToken2.balanceOf(slice.target));
        });
    });

    describe("deposit", function () {
        it("Should deposit to AutoCompounder and get aToken", async function () {
            const {
                slice,
                owner,
                autoCompounder1,
                vault1,
                stakingToken1,
            } = await deployFixture();
            const allocationPercentage1 = 4000;
            const amountToDeposit = ethers.parseUnits("50", 12);

            // Add tracking tokens
            await slice.addAllocation(
                autoCompounder1.target,
                chainlinkAggregatorMockAddress,
                allocationPercentage1
            );

            console.log("Tracking tokens added");

            // Deposit to Slice
            await stakingToken1.approve(slice.target, amountToDeposit);
            const depositAutoCompounderTx1 = await slice.deposit(autoCompounder1.target, amountToDeposit);

            await expect(
                depositAutoCompounderTx1
            ).to.emit(slice, "Deposit")
                .withArgs(autoCompounder1, owner.address, amountToDeposit);

            const exchangeRate = await autoCompounder1.exchangeRate();

            // Check user received sTokens
            await expect(
                depositAutoCompounderTx1
            ).to.changeTokenBalance(slice, owner.address, amountToDeposit / exchangeRate);
        });

        it("Should revert if invalid amount to deposit", async function () {
            const {
                slice,
                autoCompounder1,
            } = await deployFixture();
            const amountToDeposit = 0;

            await expect(
                slice.deposit(autoCompounder1.target, amountToDeposit)
            ).to.be.revertedWith("Slice: Invalid amount");
        });

        it("Should revert if allocation for the deposited token doesn't exist", async function () {
            const {
                slice,
            } = await deployFixture();
            const amountToDeposit = ethers.parseUnits("50", 12);

            await expect(
                slice.deposit(ZeroAddress, amountToDeposit)
            ).to.be.revertedWith("Slice: Allocation for the token doesn't exist");
        });
    });

    describe("withdraw", function () {
        it("Should withdraw", async function () {
            const {
                slice,
                owner,
                autoCompounder1,
                stakingToken1,
            } = await deployFixture();
            const allocationPercentage1 = 4000;
            const amountToDeposit = ethers.parseUnits("50", 12);
            const amountToWithdraw = ethers.parseUnits("25", 12);

            // Add tracking tokens
            await slice.addAllocation(
                autoCompounder1.target,
                chainlinkAggregatorMockAddress,
                allocationPercentage1
            );

            // Deposit to Slice
            await stakingToken1.approve(slice.target, amountToDeposit);
            await slice.deposit(autoCompounder1.target, amountToDeposit);

            const tx = await slice.withdraw(amountToWithdraw);

            console.log(tx.hash);

            const share = amountToWithdraw / await slice.totalSupply();

            await expect(
                tx
            ).to.emit(slice, "Withdraw")
                .withArgs(
                    autoCompounder1.target,
                    owner.address,
                    amountToDeposit * share
                );
        });

        it("Should revert if invalid amount to withdraw", async function () {
            const {
                slice,
                autoCompounder1,
                stakingToken1,
            } = await deployFixture();
            const allocationPercentage1 = 4000;
            const amountToDeposit = ethers.parseUnits("50", 12);
            const amountToWithdraw = 0;

            // Add tracking tokens
            await slice.addAllocation(
                autoCompounder1.target,
                chainlinkAggregatorMockAddress,
                allocationPercentage1
            );

            // Deposit to Slice
            await stakingToken1.approve(slice.target, amountToDeposit);
            await slice.deposit(autoCompounder1.target, amountToDeposit);

            await expect(
                slice.withdraw(amountToWithdraw)
            ).to.be.revertedWith("Slice: Invalid amount");
        });
    });

    describe("addAllocation", function () {
        it("Should add token allocation", async function () {
            const { slice, owner, autoCompounder1, stakingToken1 } = await deployFixture();
            const allocationPercentage = 4000;

            const tx = await slice.addAllocation(
                autoCompounder1.target,
                chainlinkAggregatorMockAddress,
                allocationPercentage,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(slice, "AllocationAdded")
                .withArgs(autoCompounder1.target, stakingToken1.target, chainlinkAggregatorMockAddress, allocationPercentage);
        });

        it("Should revert if zero token address", async function () {
            const { slice } = await deployFixture();
            const allocationPercentage = 4000;

            await expect(
                slice.addAllocation(
                    ZeroAddress,
                    chainlinkAggregatorMockAddress,
                    allocationPercentage,
                )
            ).to.be.revertedWith("Slice: Invalid aToken address");
        });

        it("Should revert if invalid price id", async function () {
            const { slice, autoCompounder1 } = await deployFixture();
            const allocationPercentage = 4000;

            await expect(
                slice.addAllocation(
                    autoCompounder1.target,
                    ZeroAddress,
                    allocationPercentage,
                )
            ).to.be.revertedWith("Slice: Invalid price feed address");
        });

        it("Should revert if invalid percentage", async function () {
            const { slice, autoCompounder1 } = await deployFixture();
            const allocationPercentage = 0;

            await expect(
                slice.addAllocation(
                    autoCompounder1.target,
                    chainlinkAggregatorMockAddress,
                    allocationPercentage,
                )
            ).to.be.revertedWith("Slice: Invalid allocation percentage");
        });

        it("Should revert if token already added", async function () {
            const { slice, owner, autoCompounder1 } = await deployFixture();
            const allocationPercentage = 4000;

            const tx = await slice.addAllocation(
                autoCompounder1.target,
                chainlinkAggregatorMockAddress,
                allocationPercentage,
                { from: owner.address, gasLimit: 3000000 }
            );

            await expect(
                slice.addAllocation(
                    autoCompounder1.target,
                    chainlinkAggregatorMockAddress,
                    allocationPercentage,
                )
            ).to.be.revertedWith("Slice: Allocation for the passed token exists");
        });
    });

    describe("setAllocationPercentage", function () {
        it("Should change allocation percentage", async function () {
            const { slice, owner, autoCompounder1 } = await deployFixture();
            const allocationPercentage = 4000;
            const newAllocationPercentage = 5000;

            const tx = await slice.addAllocation(
                autoCompounder1.target,
                chainlinkAggregatorMockAddress,
                allocationPercentage,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(slice, "AllocationAdded");

            const setAllocationTx = await slice.setAllocationPercentage(
                autoCompounder1.target,
                newAllocationPercentage
            );

            await expect(
                setAllocationTx
            ).to.emit(slice, "AllocationPercentageChanged")
                .withArgs(autoCompounder1.target, newAllocationPercentage);
        });

        it("Should revert if token doesn't exist", async function () {
            const { slice, autoCompounder1 } = await deployFixture();
            const allocationPercentage = 4000;

            await expect(
                slice.setAllocationPercentage(
                    autoCompounder1.target,
                    allocationPercentage,
                )
            ).to.be.revertedWith("Slice: Allocation for the passed token doesn't exist");
        });

        it("Should revert if invalid percentage", async function () {
            const { slice, autoCompounder1 } = await deployFixture();
            const allocationPercentage = 0;

            await expect(
                slice.setAllocationPercentage(
                    autoCompounder1.target,
                    allocationPercentage,
                )
            ).to.be.revertedWith("Slice: Invalid percentage");
        });
    });
});
