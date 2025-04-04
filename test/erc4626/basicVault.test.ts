import { anyValue, ethers, expect, time } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";
import hre from "hardhat";
import { BigNumberish, Wallet, ZeroAddress } from "ethers";
import { VaultToken, BasicVault } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

async function deposit(vault: BasicVault, address: string, amount: BigNumberish, staker: Wallet | HardhatEthersSigner) {
    const token = await ethers.getContractAt(
        "VaultToken",
        address
    );

    await token.connect(staker).approve(vault.target, amount);

    return vault.connect(staker).deposit(amount, staker.address);
}

// constants
const testAccountAddress = "0x934b9afc8be0f78f698753a8f67131fa58cd9884";
const operatorPrKeyTest = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY_TEST || '');
const operatorAccountIdTest = AccountId.fromString(process.env.ACCOUNT_ID_TEST || '');

const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

const testAccount = new hre.ethers.Wallet(process.env.PRIVATE_KEY_TEST!, ethers.provider);

// Zero fee
const feeConfig = {
    receiver: ZeroAddress,
    token: ZeroAddress,
    feePercentage: 0,
};

const cliff = 100;
const unlockDuration = 500;

// Tests
describe("BasicVault", function () {
    async function deployFixture() {
        const [
            owner
        ] = await ethers.getSigners();

        let client = Client.forTestnet();

        client.setOperator(
            operatorAccountId,
            operatorPrKey
        );

        const VaultToken = await ethers.getContractFactory("VaultToken");
        const stakingToken = await VaultToken.deploy(
        ) as VaultToken;
        await stakingToken.waitForDeployment();

        await stakingToken.mint(testAccount.address, ethers.parseUnits("500000000", 18));

        const RewardToken = await ethers.getContractFactory("VaultToken");
        const rewardToken = await RewardToken.deploy(
        ) as VaultToken;
        await rewardToken.waitForDeployment();

        const BasicVault = await ethers.getContractFactory("BasicVault");
        const hederaVault = await BasicVault.deploy(
            stakingToken.target,
            "TST",
            "TST",
            feeConfig,
            owner.address,
            owner.address,
            cliff,
            unlockDuration
        ) as BasicVault;
        await hederaVault.waitForDeployment();

        return {
            hederaVault,
            rewardToken,
            stakingToken,
            client,
            owner,
            testAccount
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
                hederaVault.claimAllReward(0, owner.address)
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

        it("Should revert if zero receiver", async function () {
            const { hederaVault } = await deployFixture();
            const amountToDeposit = 170;

            await expect(
                hederaVault.deposit(amountToDeposit, ZeroAddress)
            ).to.be.revertedWith("HederaVault: Invalid receiver address");
        });

        it("Should revert if zero assets", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToDeposit = 0;

            await expect(
                hederaVault.deposit(amountToDeposit, owner.address)
            ).to.be.revertedWith("HederaVault: Zero shares");
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

            const previewWithdraw = await hederaVault.previewWithdraw(amountToWithdraw);
            console.log("Preview Withdraw ", previewWithdraw);

            const currentReward = await hederaVault.getUserReward(owner.address, rewardToken.target);
            console.log("Current reward: ", currentReward);

            await hederaVault.approve(hederaVault.target, amountToWithdraw);

            // Check revert if shares aren't unlocked
            await expect(
                hederaVault.withdraw(
                    amountToWithdraw,
                    owner.address,
                    owner.address
                )
            ).to.be.revertedWithCustomError(hederaVault, "ERC4626ExceededMaxWithdraw");

            // Warp time to unlock shares
            await time.increase(1000);

            const tx = await hederaVault.withdraw(
                amountToWithdraw,
                owner.address,
                owner.address
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Withdraw")
                .withArgs(owner.address, owner.address, owner.address, amountToWithdraw, previewWithdraw);

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

        it("two people, two type of reward, one withdraw, add two reward, all claim", async function () {
            const { hederaVault, owner, stakingToken, rewardToken, client, testAccount } = await deployFixture();
            const amountToWithdraw = 10;
            const amountToStake = 112412;
            const rewardToAdd = ethers.parseUnits("5000000", 18);

            const txd = await deposit(hederaVault, await stakingToken.getAddress(), amountToStake, owner);

            console.log(txd.hash);

            // Change account and deposit
            client.setOperator(
                operatorAccountIdTest,
                operatorPrKeyTest
            );
            const txp = await deposit(hederaVault, await stakingToken.getAddress(), amountToStake, testAccount);

            console.log(txp.hash);

            // Change account and add reward
            client.setOperator(
                operatorAccountId,
                operatorPrKey
            );
            await rewardToken.approve(hederaVault.target, rewardToAdd);

            await hederaVault.connect(owner).addReward(rewardToken.target, rewardToAdd);

            const currentRewardOwner = await hederaVault.getAllRewards(owner.address);
            const currentRewardStaker = await hederaVault.getAllRewards(testAccountAddress);
            console.log("Current reward owner: ", currentRewardOwner);
            console.log("Current reward staker: ", currentRewardStaker);

            await hederaVault.approve(hederaVault.target, amountToWithdraw);

            // Warp time to unlock shares
            await time.increase(1000);

            const tx = await hederaVault.withdraw(
                amountToWithdraw,
                owner.address,
                owner.address,
                { gasLimit: 3000000 }
            );

            const currentRewardOwner1 = await hederaVault.getAllRewards(owner.address);
            const currentRewardStaker2 = await hederaVault.getAllRewards(testAccountAddress);
            console.log("Current reward owner: ", currentRewardOwner1);
            console.log("Current reward staker: ", currentRewardStaker2);

            await expect(
                tx
            ).to.emit(hederaVault, "Withdraw")
                .withArgs(owner.address, owner.address, owner.address, amountToWithdraw, anyValue);

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

            // Change account and claim reward
            client.setOperator(
                operatorAccountIdTest,
                operatorPrKeyTest
            );
            const txClaim = await hederaVault.connect(testAccount).claimAllReward(0, testAccountAddress);

            const currentRewardStaker3 = await hederaVault.getAllRewards(testAccountAddress);
            console.log("Current reward staker: ", currentRewardStaker3);

            // Check user claimed reward
            await expect(
                txClaim
            ).to.changeTokenBalance(
                rewardToken,
                testAccountAddress,
                197840253229750
            );
        });

        it("Should revert if invalid receiver", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToWithdraw = 10;

            await expect(
                hederaVault.withdraw(amountToWithdraw, ZeroAddress, owner.address)
            ).to.be.revertedWith("HederaVault: Invalid receiver address");
        });

        it("Should revert if zero assets", async function () {
            const { hederaVault, owner, rewardToken, stakingToken } = await deployFixture();
            const amountToDeposit = 170;
            const amountToWithdraw = 0;
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

            const previewWithdraw = await hederaVault.previewWithdraw(amountToWithdraw);
            console.log("Preview Withdraw ", previewWithdraw);

            await hederaVault.approve(hederaVault.target, amountToWithdraw);

            await expect(
                hederaVault.withdraw(amountToWithdraw, owner.address, owner.address)
            ).to.be.revertedWith("HederaVault: Zero shares");
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
                owner.address
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

        it("Should revert if zero receiver", async function () {
            const { hederaVault } = await deployFixture();
            const amountToMint = 10;

            await expect(
                hederaVault.mint(amountToMint, ZeroAddress)
            ).to.be.revertedWith("HederaVault: Invalid receiver address");
        });

        it("Should revert if zero shares", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToMint = 0;

            await expect(
                hederaVault.mint(amountToMint, owner.address)
            ).to.be.revertedWith("HederaVault: Zero shares");
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
            const addRewardTx = await hederaVault.addReward(rewardToken.target, rewardAmount);
            console.log(addRewardTx.hash);

            const currentReward = await hederaVault.getUserReward(owner.address, rewardToken.target);
            console.log("Current reward: ", currentReward);

            const tokensAmount = await hederaVault.previewRedeem(amountToRedeem);
            console.log("Preview redeem ", tokensAmount);

            await hederaVault.approve(hederaVault.target, amountToRedeem);

            // Check revert if shares aren't unlocked
            await expect(
                hederaVault.redeem(
                    amountToRedeem,
                    owner.address,
                    owner.address
                )
            ).to.be.revertedWithCustomError(hederaVault, "ERC4626ExceededMaxRedeem");

            // Warp time to unlock shares
            await time.increase(1000);

            const tx = await hederaVault.redeem(
                amountToRedeem,
                owner.address,
                owner.address
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Withdraw")
                .withArgs(owner.address, owner.address, owner.address, amountToRedeem, anyValue);

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
            const { hederaVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToReedem = 0;
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
            const addRewardTx = await hederaVault.addReward(rewardToken.target, rewardAmount);
            console.log(addRewardTx.hash);

            await expect(
                hederaVault.redeem(amountToReedem, owner.address, owner.address,)
            ).to.be.revertedWith("HederaVault: Zero assets");
        });

        it("Should revert if invalid receiver", async function () {
            const { hederaVault, owner } = await deployFixture();
            const amountToReedem = 10;

            await expect(
                hederaVault.redeem(amountToReedem, ZeroAddress, owner.address,)
            ).to.be.revertedWith("HederaVault: Invalid receiver address");
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
                    rewardAmount
                )
            ).to.be.revertedWith("HederaVault: Amount can't be zero");
        });

        it("Should revert if reward token is staking token", async function () {
            const { hederaVault, stakingToken } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                hederaVault.addReward(
                    stakingToken.target,
                    rewardAmount
                )
            ).to.be.revertedWith("HederaVault: Reward and Staking tokens cannot be same");
        });

        it("Should revert if no token staked yet", async function () {
            const { hederaVault, rewardToken } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                hederaVault.addReward(
                    rewardToken.target,
                    rewardAmount
                )
            ).to.be.revertedWith("HederaVault: No token staked yet");
        });

        it("Should revert if invalid reward token", async function () {
            const { hederaVault } = await deployFixture();
            const rewardAmount = 10;

            await expect(
                hederaVault.addReward(
                    ZeroAddress,
                    rewardAmount
                )
            ).to.be.revertedWith("HederaVault: Invalid reward token");
        });
    });

    describe("flow tests", function () {
        it("two people, two withdraw, add reward, all claim", async function () {
            const { hederaVault, owner, testAccount, stakingToken, rewardToken, client } = await deployFixture();
            const amountToWithdraw = 100;
            const amountToStake = 112412;
            const rewardToAdd = ethers.parseUnits("5000000", 18);

            // Stake
            const ownerDeposit = await deposit(hederaVault, await stakingToken.getAddress(), amountToStake, owner);
            // Change account
            client.setOperator(
                operatorAccountIdTest,
                operatorPrKeyTest
            );
            const stakerDeposit = await deposit(hederaVault, await stakingToken.getAddress(), amountToStake, testAccount);
            console.log("Owner deposit: ", ownerDeposit.hash);
            console.log("Staker deposit: ", stakerDeposit.hash);

            // Add reward
            client.setOperator(
                operatorAccountId,
                operatorPrKey
            );
            await rewardToken.approve(hederaVault.target, rewardToAdd);
            await hederaVault.connect(owner).addReward(rewardToken.target, rewardToAdd);

            const currentRewardOwner = await hederaVault.getAllRewards(owner.address);
            const currentRewardStaker = await hederaVault.getAllRewards(testAccount.address);
            console.log("Current reward owner after deposit: ", currentRewardOwner);
            console.log("Current reward staker after deposit: ", currentRewardStaker);

            // Withdraw
            client.setOperator(
                operatorAccountId,
                operatorPrKey
            );
            await hederaVault.approve(hederaVault.target, amountToWithdraw);

            const ownerWithdrawTx = await hederaVault.withdraw(
                amountToWithdraw,
                owner.address,
                owner.address,
                { gasLimit: 3000000 }
            );

            // Change account
            client.setOperator(
                operatorAccountIdTest,
                operatorPrKeyTest
            );
            await hederaVault.connect(testAccount).approve(hederaVault.target, amountToWithdraw);

            const stakerWithdrawTx = await hederaVault.connect(testAccount).withdraw(
                amountToWithdraw,
                testAccount.address,
                testAccount.address,
                { gasLimit: 3000000 }
            );

            const currentRewardOwner1 = await hederaVault.getAllRewards(owner.address);
            const currentRewardStaker1 = await hederaVault.getAllRewards(testAccount.address);
            console.log("Current reward owner after withdraw: ", currentRewardOwner1);
            console.log("Current reward staker after withdraw: ", currentRewardStaker1);

            // Check reward gt 0 as long as withdrawn amount lt staked amount
            expect(
                currentRewardOwner1[0]
            ).to.be.gt(0);
            expect(
                currentRewardStaker1[0]
            ).to.be.gt(0);

            // Check share was transferred to contract
            await expect(
                ownerWithdrawTx
            ).to.changeTokenBalance(
                hederaVault,
                owner,
                -amountToWithdraw
            );
            // Check user received staking token
            await expect(
                ownerWithdrawTx
            ).to.changeTokenBalance(
                stakingToken,
                owner,
                amountToWithdraw
            );
            // Check user received reward token
            await expect(
                ownerWithdrawTx
            ).to.changeTokenBalance(
                rewardToken,
                owner,
                197840253229750
            );

            await expect(
                stakerWithdrawTx
            ).to.changeTokenBalance(
                hederaVault,
                testAccount,
                -amountToWithdraw
            );
            await expect(
                stakerWithdrawTx
            ).to.changeTokenBalance(
                stakingToken,
                testAccount,
                amountToWithdraw
            );
            await expect(
                stakerWithdrawTx
            ).to.changeTokenBalance(
                rewardToken,
                testAccount,
                197840253229750
            );

            // Add reward
            client.setOperator(
                operatorAccountId,
                operatorPrKey
            );
            await rewardToken.approve(hederaVault.target, rewardToAdd);
            await hederaVault.connect(owner).addReward(rewardToken.target, rewardToAdd);

            const currentRewardOwner2 = await hederaVault.getAllRewards(owner.address);
            const currentRewardStaker2 = await hederaVault.getAllRewards(testAccount.address);
            console.log("Current reward owner after adding reward: ", currentRewardOwner2);
            console.log("Current reward staker after adding reward: ", currentRewardStaker2);

            console.log("Reward Owner balance before claim", await rewardToken.balanceOf(owner.address));
            console.log("Reward Staker balance before claim", await rewardToken.balanceOf(testAccount.address));

            const ownerClaimTx = await hederaVault.connect(owner).claimAllReward(0, owner.address);
            client.setOperator(
                operatorAccountIdTest,
                operatorPrKeyTest
            );
            const stakerClaimTx = await hederaVault.connect(testAccount).claimAllReward(0, testAccount.address);

            // Check claim success
            await expect(
                ownerClaimTx
            ).to.changeTokenBalance(
                rewardToken,
                owner,
                198192714817855
            );
            await expect(
                stakerClaimTx
            ).to.changeTokenBalance(
                rewardToken,
                testAccount,
                198192714817855
            );

            console.log("Reward Owner balance after claim", await rewardToken.balanceOf(owner.address));
            console.log("Reward Staker balance after claim", await rewardToken.balanceOf(testAccount.address));

            const currentRewardOwner3 = await hederaVault.getAllRewards(owner.address);
            const currentRewardStaker3 = await hederaVault.getAllRewards(testAccount.address);
            console.log("Current reward owner after claim: ", currentRewardOwner3);
            console.log("Current reward staker after claim: ", currentRewardStaker3);
        });
    });
});
