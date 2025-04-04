import { anyValue, ethers, expect, time } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";
import { BigNumberish, Wallet, ZeroAddress } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { VaultToken, AsyncVault } from "../../typechain-types";

import hre from "hardhat";

async function requestDeposit(vault: AsyncVault, address: string, amount: BigNumberish, staker: Wallet | HardhatEthersSigner) {
    const token = await ethers.getContractAt(
        "VaultToken",
        address
    );

    await token.connect(staker).approve(vault.target, amount);

    return vault.connect(staker).requestDeposit(amount, staker.address, staker.address);
}

// constants
const testAccountAddress = "0x934b9afc8be0f78f698753a8f67131fa58cd9884";
const operatorPrKeyTest = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY_TEST || '');
const operatorAccountIdTest = AccountId.fromString(process.env.ACCOUNT_ID_TEST || '');

const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

const testAccount = new hre.ethers.Wallet(process.env.PRIVATE_KEY_TEST!, ethers.provider);

const cliff = 100;
const unlockDuration = 500;

// Tests
describe("AsyncVault", function () {
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

        const VaultToken = await ethers.getContractFactory("VaultToken");

        const stakingToken = await VaultToken.deploy(
        ) as VaultToken;
        await stakingToken.waitForDeployment();

        await stakingToken.mint(testAccount.address, ethers.parseUnits("500000000", 18));

        const rewardToken = await VaultToken.deploy(
        ) as VaultToken;
        await rewardToken.waitForDeployment();

        // Zero fee
        const feeConfig = {
            receiver: ZeroAddress,
            token: ZeroAddress,
            feePercentage: 0,
        };

        const AsyncVault = await ethers.getContractFactory("AsyncVault");
        const asyncVault = await AsyncVault.deploy(
            stakingToken.target,
            "TST",
            "TST",
            feeConfig,
            owner.address,
            owner.address,
            cliff,
            unlockDuration
        ) as AsyncVault;
        await asyncVault.waitForDeployment();

        return {
            asyncVault,
            rewardToken,
            stakingToken,
            client,
            owner,
            testAccount,
        };
    }

    describe("requestDeposit", function () {
        it("Should stake the staking token and claim deposit", async function () {
            const { asyncVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToDeposit = 170;
            const rewardAmount = 5000000000;

            const tx = await requestDeposit(
                asyncVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            await expect(
                tx
            ).to.emit(asyncVault, "DepositRequested")
                .withArgs(owner.address, owner.address, owner.address, amountToDeposit);

            // Check staking token was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                stakingToken,
                asyncVault,
                amountToDeposit
            );

            // Claim deposit
            const depositTx = await asyncVault["deposit(uint256,address)"](amountToDeposit, owner.address);

            await expect(
                depositTx
            ).to.emit(asyncVault, "Deposit")
                .withArgs(owner.address, owner.address, amountToDeposit, amountToDeposit);

            // Add reward
            await rewardToken.approve(asyncVault.target, rewardAmount);
            const addRewardTx = await asyncVault.addReward(rewardToken.target, rewardAmount);
            console.log("Reward added: ", addRewardTx.hash);

            // Claim reward
            const claimRewardTx = await asyncVault.claimAllReward(0, owner.address);

            // Check reward received
            await expect(
                claimRewardTx
            ).to.changeTokenBalance(
                rewardToken,
                owner.address,
                173010
            );
            // Check shares received
            await expect(
                depositTx
            ).to.changeTokenBalance(
                asyncVault,
                owner.address,
                amountToDeposit
            );
        });

        it("Should revert if max deposit request", async function () {
            const { asyncVault, owner, stakingToken } = await deployFixture();
            const amountToDeposit = 170;
            const amountToClaimDeposit = 180;

            // Request deposit
            await requestDeposit(
                asyncVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            // Claim deposit
            await expect(
                asyncVault["deposit(uint256,address)"](amountToClaimDeposit, owner.address)
            ).to.be.revertedWithCustomError(asyncVault, "MaxDepositRequestExceeded")
                .withArgs(owner.address, amountToClaimDeposit, amountToDeposit);
        });

        it("Should revert if zero shares", async function () {
            const { asyncVault, owner } = await deployFixture();
            const amountToDeposit = 0;

            await expect(
                asyncVault.requestDeposit(amountToDeposit, owner.address, owner.address)
            ).to.be.revertedWith("AsyncVault: Invalid asset amount");
        });

        it("Should revert if invalid controller or owner", async function () {
            const { asyncVault, owner, stakingToken } = await deployFixture();
            const amountToDeposit = 170;

            await stakingToken.approve(asyncVault.target, amountToDeposit);

            await expect(
                asyncVault.requestDeposit(amountToDeposit, owner.address, ZeroAddress)
            ).to.be.revertedWith("AsyncVault: Invalid owner address");

            await expect(
                asyncVault.requestDeposit(amountToDeposit, ZeroAddress, owner.address)
            ).to.be.revertedWith("AsyncVault: Invalid owner address");
        });
    });

    describe("requestRedeem", function () {
        it("Should redeem tokens, return assets and claim reward", async function () {
            const { asyncVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToRedeem = 170;
            const amountToDeposit = 170;
            const rewardAmount = 5000000000;
            const sharesLockTime = 1000

            // Set lock shares period
            const lockSharesTx = await asyncVault.setSharesLockTime(sharesLockTime);
            await expect(
                lockSharesTx
            ).to.emit(asyncVault, "SetSharesLockTime")
                .withArgs(sharesLockTime);

            // Request deposit
            await requestDeposit(
                asyncVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            // Claim deposit
            await asyncVault["deposit(uint256,address)"](amountToDeposit, owner.address);

            // Add reward
            await rewardToken.approve(asyncVault.target, rewardAmount);
            await asyncVault.addReward(rewardToken.target, rewardAmount);

            // Check revert if shares aren't unlocked
            await expect(
                asyncVault.redeem(
                    amountToRedeem,
                    owner.address,
                    owner.address
                )
            ).to.be.revertedWithCustomError(asyncVault, "MaxRedeemRequestExceeded");

            // Increase block timestamp to unlock shares
            await time.increase(1100);

            await asyncVault.approve(asyncVault.target, amountToRedeem);

            // Request redeem
            const requestRedeemTx = await asyncVault.requestRedeem(
                amountToRedeem,
                owner.address,
                owner.address
            );

            await expect(
                requestRedeemTx
            ).to.emit(asyncVault, "RedeemRequested")
                .withArgs(owner.address, owner.address, owner.address, amountToRedeem);

            // Claim redeem
            const redeemTx = await asyncVault.redeem(amountToRedeem, owner.address, owner.address);

            await expect(
                redeemTx
            ).to.emit(asyncVault, "Withdraw")
                .withArgs(owner.address, owner.address, owner.address, amountToRedeem, amountToRedeem);

            // Check assets received
            await expect(
                redeemTx
            ).to.changeTokenBalance(
                stakingToken,
                owner.address,
                amountToRedeem
            );
            // Check reward received
            await expect(
                redeemTx
            ).to.changeTokenBalance(
                rewardToken,
                owner.address,
                173010
            );
        });

        it("Should revert if max redeem request exceeded", async function () {
            const { asyncVault, owner, stakingToken } = await deployFixture();
            const amountToDeposit = 170;
            const amountToRedeem = 180;

            // Request deposit
            await requestDeposit(
                asyncVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            // Claim deposit
            await asyncVault["deposit(uint256,address)"](amountToDeposit, owner.address);

            await expect(
                asyncVault.redeem(amountToRedeem, owner.address, owner.address)
            ).to.be.revertedWithCustomError(asyncVault, "MaxRedeemRequestExceeded")
                .withArgs(owner.address, amountToRedeem, 0);
        });

        it("Should revert if zero shares", async function () {
            const { asyncVault, owner } = await deployFixture();
            const amountToRedeem = 0;

            await expect(
                asyncVault.requestRedeem(amountToRedeem, owner.address, owner.address)
            ).to.be.revertedWith("AsyncVault: Invalid shares amount");
        });

        it("Should revert if invalid controller or owner", async function () {
            const { asyncVault, owner } = await deployFixture();
            const amountToRedeem = 10;

            await expect(
                asyncVault.requestRedeem(amountToRedeem, owner.address, ZeroAddress)
            ).to.be.revertedWith("AsyncVault: Invalid owner address");

            await expect(
                asyncVault.requestRedeem(amountToRedeem, ZeroAddress, owner.address)
            ).to.be.revertedWith("AsyncVault: Invalid owner address");
        });
    });

    describe.only("withdraw", function () {
        it("Should stake the staking token, claim deposit and withdraw", async function () {
            const { asyncVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToDeposit = 170;
            const amountToWithdraw = 170;
            const rewardAmount = 5000000000;

            const tx = await requestDeposit(
                asyncVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            await expect(
                tx
            ).to.emit(asyncVault, "DepositRequested")
                .withArgs(owner.address, owner.address, owner.address, amountToDeposit);

            // Check staking token was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                stakingToken,
                asyncVault,
                amountToDeposit
            );

            // Claim deposit
            const depositTx = await asyncVault["deposit(uint256,address)"](amountToDeposit, owner.address);

            await expect(
                depositTx
            ).to.emit(asyncVault, "Deposit")
                .withArgs(owner.address, owner.address, amountToDeposit, amountToDeposit);

            // Check shares received
            await expect(
                depositTx
            ).to.changeTokenBalance(
                asyncVault,
                owner.address,
                amountToDeposit
            );

            // Add reward
            await rewardToken.approve(asyncVault.target, rewardAmount);
            const addRewardTx = await asyncVault.addReward(rewardToken.target, rewardAmount);
            console.log("Reward added: ", addRewardTx.hash);

            // Request redeem
            const requestRedeemTx = await asyncVault.requestRedeem(amountToWithdraw, owner.address, owner.address);

            await expect(
                requestRedeemTx
            ).to.emit(asyncVault, "RedeemRequested")
                .withArgs(owner.address, owner.address, owner.address, amountToWithdraw);

            // Check revert if shares aren't unlocked
            await expect(
                asyncVault.withdraw(
                    amountToWithdraw,
                    owner.address,
                    owner.address
                )
            ).to.be.revertedWithCustomError(asyncVault, "ERC4626ExceededMaxWithdraw");

            // Increase block timestamp to unlock shares
            await time.increase(1100);

            // Withdraw
            const withdrawTx = await asyncVault.withdraw(amountToWithdraw, owner.address, owner.address);

            // Check reward received
            await expect(
                withdrawTx
            ).to.changeTokenBalance(
                rewardToken,
                owner.address,
                173010
            );
            // Check assets received
            await expect(
                withdrawTx
            ).to.changeTokenBalance(
                stakingToken,
                owner.address,
                amountToWithdraw
            );
        });

        it("Should revert if max redeem request for withdraw exceeded", async function () {
            const { asyncVault, owner, stakingToken } = await deployFixture();
            const amountToDeposit = 170;
            const amountToRedeem = 180;

            // Request deposit
            await requestDeposit(
                asyncVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            // Claim deposit
            await asyncVault["deposit(uint256,address)"](amountToDeposit, owner.address);

            await expect(
                asyncVault.withdraw(amountToRedeem, owner.address, owner.address)
            ).to.be.revertedWithCustomError(asyncVault, "ERC4626ExceededMaxWithdraw")
                .withArgs(owner.address, amountToRedeem, 0);
        });
    });

    describe("addReward", function () {
        it("Should add reward to the Vault", async function () {
            const { asyncVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToDeposit = 100;
            const rewardAmount = 100000;

            await requestDeposit(
                asyncVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            await rewardToken.approve(asyncVault.target, rewardAmount);

            const tx = await asyncVault.addReward(
                rewardToken.target,
                rewardAmount
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(asyncVault, "RewardAdded")
                .withArgs(rewardToken.target, rewardAmount);

            // Check reward token was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                rewardToken,
                asyncVault.target,
                rewardAmount
            );

            await rewardToken.approve(asyncVault.target, rewardAmount);

            const secondTx = await asyncVault.addReward(
                rewardToken.target,
                rewardAmount
            );

            await expect(
                secondTx
            ).to.emit(asyncVault, "RewardAdded")
                .withArgs(rewardToken.target, rewardAmount);
        });

        it("Should revert if amount is zero", async function () {
            const { asyncVault, rewardToken } = await deployFixture();
            const rewardAmount = 0;

            await expect(
                asyncVault.addReward(
                    rewardToken.target,
                    rewardAmount,

                )
            ).to.be.revertedWith("AsyncVault: Amount can't be zero");
        });

        it("Should revert if reward token is staking token", async function () {
            const { asyncVault, stakingToken } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                asyncVault.addReward(
                    stakingToken.target,
                    rewardAmount,

                )
            ).to.be.revertedWith("AsyncVault: Reward and Staking tokens cannot be same");
        });

        it("Should revert if no token staked yet", async function () {
            const { asyncVault, rewardToken } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                asyncVault.addReward(
                    rewardToken.target,
                    rewardAmount,

                )
            ).to.be.revertedWith("AsyncVault: No token staked yet");
        });

        it("Should revert if invalid reward token", async function () {
            const { asyncVault } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                asyncVault.addReward(
                    ZeroAddress,
                    rewardAmount,

                )
            ).to.be.revertedWith("AsyncVault: Invalid reward token");
        });
    });
});
