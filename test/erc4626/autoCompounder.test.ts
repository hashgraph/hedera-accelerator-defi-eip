import { anyValue, ethers, expect, time } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";
import { ZeroAddress } from "ethers";
import { VaultToken, BasicVault, AsyncVault, AutoCompounder, UniswapRouterMock } from "../../typechain-types";
import hre from "hardhat";

import factoryAbi from "@uniswap/v2-core/build/UniswapV2Factory.json";
import routerAbi from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import wethAbi from "@uniswap/v2-periphery/build/WETH9.json";

import { VaultType, deployBasicVault, deployAsyncVault } from "./helper";

// constants
// const testAccountAddress = "0x934b9afc8be0f78f698753a8f67131fa58cd9884";
// const operatorPrKeyTest = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY_TEST || '');
// const operatorAccountIdTest = AccountId.fromString(process.env.ACCOUNT_ID_TEST || '');

// const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
// const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

// const testAccount = new hre.ethers.Wallet(process.env.PRIVATE_KEY_TEST!, ethers.provider);

// Zero fee
const feeConfig = {
    receiver: ZeroAddress,
    token: ZeroAddress,
    feePercentage: 0,
};

const unlockDuration1 = 300;
const unlockDuration2 = 500;

// Tests
describe("AutoCompounder", function () {
    async function deployFixture(vaultType: VaultType) {
        const [
            owner,
            staker
        ] = await ethers.getSigners();

        let client = Client.forTestnet();

        const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
        const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

        client.setOperator(
            operatorAccountId,
            operatorPrKey
        );

        // Uniswap
        const UniswapV2Factory = await ethers.getContractFactory(factoryAbi.abi, factoryAbi.bytecode, owner);
        const uniswapV2Factory = await UniswapV2Factory.deploy(
            owner.address,
        );
        await uniswapV2Factory.waitForDeployment();

        const WETH = await ethers.getContractFactory(wethAbi.abi, wethAbi.bytecode, owner);
        const weth = await WETH.deploy();
        await weth.waitForDeployment();

        const UniswapV2Router02 = await ethers.getContractFactory(routerAbi.abi, routerAbi.bytecode, owner);
        const uniswapV2Router02 = await UniswapV2Router02.deploy(
            uniswapV2Factory.target,
            weth.target
        ) as UniswapRouterMock;
        await uniswapV2Router02.waitForDeployment();

        // Vault
        const VaultToken = await ethers.getContractFactory("VaultToken");
        const stakingToken = await VaultToken.deploy(
        ) as VaultToken;
        await stakingToken.waitForDeployment();

        // await stakingToken.mint(testAccount.address, ethers.parseUnits("500000000", 18));

        const RewardToken = await ethers.getContractFactory("VaultToken");
        const rewardToken = await RewardToken.deploy(
        ) as VaultToken;
        await rewardToken.waitForDeployment();

        let vault;
        if (vaultType === VaultType.Basic) {
            vault = await deployBasicVault(stakingToken, owner, feeConfig, unlockDuration1) as BasicVault;
        } else {
            vault = await deployAsyncVault(stakingToken, owner, feeConfig, unlockDuration2) as AsyncVault;
        }

        const AutoCompounder = await ethers.getContractFactory("AutoCompounder");
        const autoCompounder = await AutoCompounder.deploy(
            uniswapV2Router02,
            vault.target,
            rewardToken.target, // TODO: change to real USDC
            "TST",
            "TST",
            owner.address
        ) as AutoCompounder;
        await autoCompounder.waitForDeployment();

        return {
            autoCompounder,
            vault,
            uniswapV2Router02,
            stakingToken,
            rewardToken,
            client,
            owner,
        };
    }

    describe("deposit", function () {
        it("Should deposit tokens and return shares", async function () {
            const { autoCompounder, stakingToken, owner, vault } = await deployFixture(VaultType.Basic);
            const amountToDeposit = ethers.parseUnits("170", 18);

            await stakingToken.approve(autoCompounder.target, amountToDeposit);

            const tx = await autoCompounder.deposit(
                amountToDeposit,
                owner.address,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounder, "Deposit")
                .withArgs(owner.address, amountToDeposit, anyValue);

            // Check share token was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                vault,
                autoCompounder.target,
                amountToDeposit
            );
            // Check auto token was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                autoCompounder,
                owner.address,
                amountToDeposit / await autoCompounder.exchangeRate()
            );
        });

        it("Should deposit to Async Vault tokens and return shares", async function () {
            const { autoCompounder, stakingToken, owner, vault } = await deployFixture(VaultType.Async);
            const amountToDeposit = ethers.parseUnits("170", 18);

            await stakingToken.approve(autoCompounder.target, amountToDeposit);

            const tx = await autoCompounder.deposit(
                amountToDeposit,
                owner.address,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log("Deposit: ", tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounder, "Deposit")
                .withArgs(owner.address, amountToDeposit, anyValue);

            await expect(
                tx
            ).to.emit(vault, "DepositRequested")
                .withArgs(autoCompounder.target, autoCompounder.target, autoCompounder.target, amountToDeposit);

            // Check share token was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                vault,
                autoCompounder.target,
                amountToDeposit
            );
            // Check aToken was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                autoCompounder,
                owner.address,
                amountToDeposit / await autoCompounder.exchangeRate()
            );
        });

        it("Should revert in case of zero assets", async function () {
            const { autoCompounder, owner } = await deployFixture(VaultType.Basic);
            const amountToDeposit = 0;

            await expect(
                autoCompounder.deposit(
                    amountToDeposit,
                    owner.address
                )
            ).to.be.revertedWith("AutoCompounder: Invalid assets amount");
        });

        it("Should revert if invalid receiver", async function () {
            const { autoCompounder } = await deployFixture(VaultType.Basic);
            const amountToDeposit = 170;

            await expect(
                autoCompounder.deposit(
                    amountToDeposit,
                    ZeroAddress
                )
            ).to.be.revertedWith("AutoCompounder: Invalid receiver address");
        });
    });

    describe("withdraw", function () {
        it("Should withdraw tokens", async function () {
            const { autoCompounder, vault, stakingToken, rewardToken, owner } = await deployFixture(VaultType.Basic);
            const amountToWithdraw = ethers.parseUnits("10", 1);
            const rewardAmount = ethers.parseUnits("5000000", 18);
            const amountToDeposit = 170;

            await stakingToken.approve(autoCompounder.target, amountToDeposit);

            await autoCompounder.deposit(
                amountToDeposit,
                owner.address,
                { from: owner.address, gasLimit: 3000000 }
            );

            // Add reward to the Vault
            await rewardToken.approve(vault.target, rewardAmount);
            await vault.addReward(rewardToken.target, rewardAmount);

            await autoCompounder.approve(autoCompounder.target, 100);
            await vault.approve(autoCompounder.target, 1000);

            const exchangeRate = await autoCompounder.exchangeRate();
            const withdrawnUnderlyingAmount = exchangeRate * amountToWithdraw;

            // Warp time
            await time.increase(1000);

            const tx = await autoCompounder.withdraw(
                amountToWithdraw,
                owner.address,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log("Withdraw: ", tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounder, "Withdraw")
                .withArgs(owner.address, amountToWithdraw, anyValue);

            // Check underlying was transferred to receiver
            await expect(
                tx
            ).to.changeTokenBalance(
                stakingToken,
                owner.address,
                withdrawnUnderlyingAmount
            );
            // Check reward was transferred to receiver
            await expect(
                tx
            ).to.changeTokenBalance(
                rewardToken,
                owner.address,
                4999999999999999999999999n
            );
        });

        it("Should withdraw tokens from Async Vault", async function () {
            const { autoCompounder, vault, stakingToken, rewardToken, owner } = await deployFixture(VaultType.Async);
            const amountToWithdraw = ethers.parseUnits("10", 1);
            const rewardAmount = ethers.parseUnits("5000000", 18);
            const amountToDeposit = 170;

            await stakingToken.approve(autoCompounder.target, amountToDeposit);

            await autoCompounder.deposit(
                amountToDeposit,
                owner.address,
                { from: owner.address, gasLimit: 3000000 }
            );

            // Add reward to the Vault
            await rewardToken.approve(vault.target, rewardAmount);
            await vault.addReward(rewardToken.target, rewardAmount);

            await autoCompounder.approve(autoCompounder.target, 100);
            await vault.approve(autoCompounder.target, 1000);

            const exchangeRate = await autoCompounder.exchangeRate();
            const withdrawnUnderlyingAmount = exchangeRate * amountToWithdraw;

            // Warp time
            await time.increase(1000);

            await vault.requestRedeem(amountToWithdraw, autoCompounder.target, autoCompounder.target);

            const tx = await autoCompounder.withdraw(
                amountToWithdraw,
                owner.address,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log("Withdraw: ", tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounder, "Withdraw")
                .withArgs(owner.address, amountToWithdraw, withdrawnUnderlyingAmount);

            // Check underlying was transferred to receiver
            await expect(
                tx
            ).to.changeTokenBalance(
                stakingToken,
                owner.address,
                withdrawnUnderlyingAmount
            );
            // Check reward was transferred to receiver
            await expect(
                tx
            ).to.changeTokenBalance(
                rewardToken,
                owner.address,
                4999999999999999999999999n
            );
        });

        it("Should revert in case of zero amount of aToken", async function () {
            const { autoCompounder } = await deployFixture(VaultType.Basic);
            const amountToWithdraw = 0;

            await expect(
                autoCompounder.withdraw(
                    amountToWithdraw,
                    autoCompounder.target
                )
            ).to.be.revertedWith("AutoCompounder: Invalid aToken amount");
        });

        it("Should revert if invalid receiver", async function () {
            const { autoCompounder } = await deployFixture(VaultType.Basic);
            const amountToWithdraw = 170;

            await expect(
                autoCompounder.withdraw(
                    amountToWithdraw,
                    ZeroAddress
                )
            ).to.be.revertedWith("AutoCompounder: Invalid receiver address");
        });
    });

    describe("claim", function () {
        it("Should claim reward and reinvest", async function () {
            const { autoCompounder, vault, uniswapV2Router02, stakingToken, rewardToken, owner } = await deployFixture(VaultType.Basic);
            const amountToDeposit = 112412;
            const rewardAmount = ethers.parseUnits("5000000", 18);

            const latestBlock = await ethers.provider.getBlock("latest");
            const timestamp = latestBlock?.timestamp;

            // Add Liquidity
            await rewardToken.approve(uniswapV2Router02.target, ethers.parseUnits("5000000", 18));
            await stakingToken.approve(uniswapV2Router02.target, ethers.parseUnits("5000000", 18));

            const addLiquidityTx = await uniswapV2Router02.addLiquidity(
                rewardToken.target,
                stakingToken.target,
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                ethers.parseUnits("5000000", 18),
                owner.address,
                timestamp! + 100
            );

            console.log("Add Liquidity Tx: ", addLiquidityTx.hash);

            // Deposit
            await stakingToken.approve(autoCompounder.target, amountToDeposit);
            await autoCompounder.deposit(
                amountToDeposit,
                owner.address,
                { from: owner.address, gasLimit: 3000000 }
            );

            // Add reward to the Vault
            await rewardToken.approve(vault.target, rewardAmount);
            await vault.addReward(rewardToken.target, rewardAmount);

            console.log("Shares: ", await vault.balanceOf(autoCompounder.target));
            console.log("Reward: ", await vault.getUserReward(autoCompounder.target, rewardToken.target));

            // Claim and reinvest
            const tx = await autoCompounder.claim(
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log("Claim Tx", tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounder, "Claim");
        });
    });
});
