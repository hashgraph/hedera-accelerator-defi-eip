import { anyValue, ethers, expect } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";
import hre from "hardhat";
import { BigNumberish, ZeroAddress } from "ethers";
import { VaultToken, BasicVault } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

async function deposit(vault: BasicVault, address: string, amount: BigNumberish, staker: HardhatEthersSigner) {
    const token = await ethers.getContractAt(
        "VaultToken",
        address
    );

    await token.connect(staker).approve(vault.target, amount);

    return vault.connect(staker).deposit(amount, staker.address);
}

// constants

// Tests
describe("BasicVault", function () {
    async function deployFixture() {
        const [
            owner,
            staker,
        ] = await ethers.getSigners();

        let client = Client.forTestnet();

        const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
        const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

        client.setOperator(
            operatorAccountId,
            operatorPrKey
        );

        const erc20 = await hre.artifacts.readArtifact("contracts/erc4626/ERC20.sol:ERC20");

        const VaultToken = await ethers.getContractFactory("VaultToken");
        const stakingToken = await VaultToken.deploy(
        ) as VaultToken;
        await stakingToken.waitForDeployment();

        const RewardToken = await ethers.getContractFactory("VaultToken");
        const rewardToken = await RewardToken.deploy(
        ) as VaultToken;
        await rewardToken.waitForDeployment();

        // Zero fee
        const feeConfig = {
            receiver: ZeroAddress,
            token: ZeroAddress,
            feePercentage: 0,
        };

        const BasicVault = await ethers.getContractFactory("BasicVault");
        const hederaVault = await BasicVault.deploy(
            stakingToken.target,
            "TST",
            "TST",
            feeConfig,
            owner.address,
            owner.address
        ) as BasicVault;
        await hederaVault.waitForDeployment();

        return {
            hederaVault,
            rewardToken,
            stakingToken,
            client,
            owner,
        };
    }

    describe("deposit", function () {
        it("Should deposit tokens and return shares", async function () {
            const { hederaVault, owner, stakingToken } = await deployFixture();
            const amountToDeposit = 170;

            console.log("Preview deposit ", await hederaVault.previewDeposit(amountToDeposit));

            await stakingToken.approve(hederaVault.target, amountToDeposit);

            const tx = await hederaVault.connect(owner).deposit(
                amountToDeposit,
                owner.address,
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Deposit")
                .withArgs(owner.address, owner.address, amountToDeposit, anyValue);

            // Check staking token was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                stakingToken,
                owner.address,
                -amountToDeposit
            );
            // Check user received share
            await expect(
                tx
            ).to.changeTokenBalance(
                hederaVault,
                owner.address,
                amountToDeposit
            );
        });

        it("Should claim rewards after deposit", async function () {
            const { hederaVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToDeposit = 170;
            const rewardAmount = 50000;

            console.log("Preview deposit ", await hederaVault.previewDeposit(amountToDeposit));

            await stakingToken.approve(hederaVault.target, amountToDeposit);

            const tx = await hederaVault.connect(owner).deposit(
                amountToDeposit,
                owner.address,
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Deposit")
                .withArgs(owner.address, owner.address, amountToDeposit, anyValue);

            // Check revert if no rewards
            await expect(
                hederaVault.claimAllReward(0)
            ).to.be.revertedWith("HederaVault: No reward tokens exist");

            await rewardToken.approve(hederaVault.target, rewardAmount);

            // Add reward
            const addRewardTx = await hederaVault.addReward(rewardToken.target, rewardAmount);
            console.log(addRewardTx.hash);

            const rewards = await hederaVault.getAllRewards(owner);
            console.log("Available Reward: ", rewards);

            // Check rewards greater than 0
            expect(
                rewards[0]
            ).to.be.gt(0);

            await stakingToken.approve(hederaVault.target, amountToDeposit);

            const secondDepositTx = await hederaVault.deposit(
                amountToDeposit,
                owner.address,

            );

            console.log(secondDepositTx.hash);

            // Check reward was transferred to user
            await expect(
                secondDepositTx
            ).to.changeTokenBalance(
                rewardToken,
                owner.address,
                rewards[0]
            );
        });

        it("Should revert if zero shares", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToDeposit = 0;

            await expect(
                hederaVault.deposit(amountToDeposit, owner.address)
            ).to.be.revertedWithCustomError(hederaVault, "ZeroShares");
        });

        it("Should revert if invalid receiver", async function () {
            const { hederaVault } = await deployFixture();
            const amountToDeposit = 0;

            await expect(
                hederaVault.deposit(amountToDeposit, ZeroAddress)
            ).to.be.revertedWith("HederaVault: Invalid receiver address");
        });
    });

    describe("withdraw", function () {
        it("Should withdraw tokens", async function () {
            const { hederaVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToDeposit = 170;
            const amountToWithdraw = 10;
            const rewardAmount = 50000;

            await deposit(
                hederaVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            await rewardToken.approve(hederaVault.target, rewardAmount);

            // Add reward
            const addRewardTx = await hederaVault.addReward(rewardToken.target, rewardAmount);
            console.log(addRewardTx.hash);

            console.log("Preview Withdraw ", await hederaVault.previewWithdraw(amountToWithdraw));

            const currentReward = await hederaVault.getUserReward(owner.address, rewardToken.target);

            await hederaVault.approve(hederaVault.target, amountToWithdraw);

            const tx = await hederaVault.withdraw(
                amountToWithdraw,
                owner.address,
                owner.address,

            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Withdraw")
                .withArgs(owner.address, owner.address, amountToWithdraw, anyValue);

            // Check share was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                hederaVault,
                owner,
                -amountToWithdraw
            );
            // Check user received staking token
            await expect(
                tx
            ).to.changeTokenBalance(
                stakingToken,
                owner,
                amountToWithdraw
            );
            // Check user received reward token
            await expect(
                tx
            ).to.changeTokenBalance(
                rewardToken,
                owner,
                currentReward
            );
        });

        it("Should revert if invalid receiver", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToWithdraw = 10;

            await expect(
                hederaVault.withdraw(amountToWithdraw, ZeroAddress, owner.address)
            ).to.be.revertedWith("HederaVault: Invalid receiver address");
        });

        it("Should revert if invalid from address", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToWithdraw = 10;

            await expect(
                hederaVault.withdraw(amountToWithdraw, owner.address, ZeroAddress)
            ).to.be.revertedWith("HederaVault: Invalid from address");
        });

        it("Should revert if zero assets", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToWithdraw = 0;

            await expect(
                hederaVault.withdraw(amountToWithdraw, owner.address, owner.address)
            ).to.be.revertedWith("HederaVault: Zero assets");
        });

        it("Should revert if sender has no shares", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToWithdraw = 10;

            await expect(
                hederaVault.withdraw(amountToWithdraw, owner.address, owner.address)
            ).to.be.revertedWith("HederaVault: Not enough share on the balance");
        });
    });

    describe("mint", function () {
        it("Should mint tokens", async function () {
            const { hederaVault, owner, stakingToken } = await deployFixture();
            const amountOfShares = 1;

            const amount = await hederaVault.previewMint(amountOfShares);
            console.log("Preview Mint ", amount);

            await stakingToken.approve(hederaVault.target, amount);

            const tx = await hederaVault.connect(owner).mint(
                amountOfShares,
                owner.address,

            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Deposit")
                .withArgs(owner.address, owner.address, amountOfShares, amountOfShares);

            // Check share token was transferred to user
            await expect(
                tx
            ).to.changeTokenBalance(
                hederaVault,
                owner,
                amountOfShares
            );
        });

        it("Should revert if invalid receiver", async function () {
            const { hederaVault } = await deployFixture();
            const amountToMint = 10;

            await expect(
                hederaVault.mint(amountToMint, ZeroAddress,)
            ).to.be.revertedWith("HederaVault: Invalid receiver address");
        });

        it("Should revert if zero shares", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToMint = 0;

            await expect(
                hederaVault.mint(amountToMint, owner.address,)
            ).to.be.revertedWithCustomError(hederaVault, "ZeroShares");
        });
    });

    describe("addReward", function () {
        it("Should add reward to the Vault two times", async function () {
            const { hederaVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToDeposit = 100;
            const rewardAmount = 100000;

            await deposit(
                hederaVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            await rewardToken.approve(hederaVault.target, rewardAmount);

            const tx = await hederaVault.addReward(
                rewardToken.target,
                rewardAmount
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "RewardAdded")
                .withArgs(rewardToken.target, rewardAmount);

            // Check reward token was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                rewardToken,
                hederaVault.target,
                rewardAmount
            );

            await rewardToken.approve(hederaVault.target, rewardAmount);

            const secondTx = await hederaVault.addReward(
                rewardToken.target,
                rewardAmount
            );

            await expect(
                secondTx
            ).to.emit(hederaVault, "RewardAdded")
                .withArgs(rewardToken.target, rewardAmount);
        });

        it("Should revert if amount is zero", async function () {
            const { hederaVault, rewardToken } = await deployFixture();
            const rewardAmount = 0;

            await expect(
                hederaVault.addReward(
                    rewardToken.target,
                    rewardAmount,

                )
            ).to.be.revertedWith("HederaVault: Amount can't be zero");
        });

        it("Should revert if reward token is staking token", async function () {
            const { hederaVault, stakingToken } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                hederaVault.addReward(
                    stakingToken.target,
                    rewardAmount,

                )
            ).to.be.revertedWith("HederaVault: Reward and Staking tokens cannot be same");
        });

        it("Should revert if no token staked yet", async function () {
            const { hederaVault, rewardToken } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                hederaVault.addReward(
                    rewardToken.target,
                    rewardAmount,

                )
            ).to.be.revertedWith("HederaVault: No token staked yet");
        });

        it("Should revert if invalid reward token", async function () {
            const { hederaVault } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                hederaVault.addReward(
                    ZeroAddress,
                    rewardAmount,

                )
            ).to.be.revertedWith("HederaVault: Invalid reward token");
        });
    });

    describe("redeem", function () {
        it("Should redeem tokens", async function () {
            const { hederaVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToRedeem = 10;
            const amountToDeposit = 170;
            const rewardAmount = 50000;

            await deposit(
                hederaVault,
                await stakingToken.getAddress(),
                amountToDeposit,
                owner
            );

            await rewardToken.approve(hederaVault.target, rewardAmount);

            // Add reward
            const addRewardTx = await hederaVault.addReward(rewardToken.target, rewardAmount,);
            console.log(addRewardTx.hash);

            const currentReward = await hederaVault.getUserReward(owner.address, rewardToken.target);

            const tokensAmount = await hederaVault.previewRedeem(amountToRedeem);
            console.log("Preview redeem ", tokensAmount);

            await hederaVault.approve(hederaVault.target, amountToRedeem);

            const tx = await hederaVault.redeem(
                amountToRedeem,
                owner.address,
                owner.address,

            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Withdraw")
                .withArgs(owner.address, owner.address, tokensAmount, amountToRedeem);

            // Check share was transferred to contract
            await expect(
                tx
            ).to.changeTokenBalance(
                hederaVault,
                owner,
                -amountToRedeem
            );
            // Check user received staking token
            await expect(
                tx
            ).to.changeTokenBalance(
                stakingToken,
                owner,
                amountToRedeem
            );
            // Check user received reward token
            await expect(
                tx
            ).to.changeTokenBalance(
                rewardToken,
                owner,
                currentReward
            );
        });

        it("Should revert if zero assets", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToReedem = 0;

            await expect(
                hederaVault.redeem(amountToReedem, owner.address, owner.address,)
            ).to.be.revertedWith("HederaVault: Zero assets");
        });

        it("Should revert if sender has no shares", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToReedem = 10;

            await expect(
                hederaVault.redeem(amountToReedem, owner.address, owner.address,)
            ).to.be.revertedWith("HederaVault: Not enough share on the balance");
        });

        it("Should revert if invalid receiver", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToReedem = 10;

            await expect(
                hederaVault.redeem(amountToReedem, ZeroAddress, owner.address,)
            ).to.be.revertedWith("HederaVault: Invalid receiver address");
        });

        it("Should revert if invalid from address", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToReedem = 10;

            await expect(
                hederaVault.redeem(amountToReedem, owner.address, ZeroAddress,)
            ).to.be.revertedWith("HederaVault: Invalid from address");
        });
    });
});
