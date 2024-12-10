import { anyValue, ethers, expect } from "../setup";
import { TokenTransfer, createFungibleToken, TokenBalance, createAccount, addToken, mintToken } from "../../scripts/utils";
import { getCorrectDepositNumber } from "./helper";
import { PrivateKey, Client, AccountId, TokenAssociateTransaction, AccountBalanceQuery } from "@hashgraph/sdk";
import hre from "hardhat";

// constants
const stakingTokenId = "0.0.3757626";
const sharesTokenAddress = "0x0000000000000000000000000000000000395640";
const revertCasesVaultAddress = "0xb3C24B140BA2a69099276e55dE1885e93517C6C6";
const revertCasesVaultId = "0.0.3757631";

const newStakingTokenId = "0.0.5216102";
const newRewardTokenId = "0.0.4310077";
const rewardTokenAddress = "0x00000000000000000000000000000000004F9767";
const newSharesTokenAddress = "0x00000000000000000000000000000000004fe615";
const newSharesTokenId = "0.0.5236245";
const newVaultId = "0.0.4229240";

const vaultEr = "0x7CbACbd39208A0460D4eB7e0b3c290DDAcF761d2";
// Tests
describe("Vault", function () {
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

        const erc20 = await hre.artifacts.readArtifact("contracts/erc4626/ERC20.sol:ERC20");

        const sharesTokenAssociate = await new TokenAssociateTransaction()
            .setAccountId(operatorAccountId)
            .setTokenIds([newSharesTokenId])
            .execute(client);

        // const stakingTokenAssociate = await new TokenAssociateTransaction()
        //     .setAccountId(operatorAccountIdTest)
        //     .setTokenIds([newStakingTokenId])
        //     .execute(client);

        // const rewardTokenAssociate = await new TokenAssociateTransaction()
        //     .setAccountId(operatorAccountIdTest)
        //     .setTokenIds([newRewardTokenId])
        //     .execute(client);

        const hederaVaultRevertCases = await ethers.getContractAt(
            "HederaVault",
            revertCasesVaultAddress
        );
        const hederaVault = await ethers.getContractAt(
            "HederaVault",
            vaultEr
        );

        const rewardToken = await ethers.getContractAt(
            erc20.abi,
            rewardTokenAddress
        );

        const stakingToken = await ethers.getContractAt(
            erc20.abi,
            await hederaVault.asset()
        );

        const sharesToken = await ethers.getContractAt(
            erc20.abi,
            await hederaVault.share()
        );

        // await TokenTransfer(newStakingTokenId, operatorAccountId, "0.0.3638358", 1000, client);

        // const stakingTokenOperatorBalance = await (
        //     await TokenBalance(operatorAccountId, client)
        // ).tokens!.get(newRewardTokenId);
        // console.log("Reward token balance: ", stakingTokenOperatorBalance.toString());

        // const tx = await rewardToken.approve(hederaVault.target, 100);

        // const rewTx = await hederaVault.addReward(rewardTokenAddress, 100, { gasLimit: 3000000 });

        return {
            hederaVault,
            hederaVaultRevertCases,
            rewardToken,
            stakingToken,
            sharesToken,
            client,
            owner,
        };
    }

    describe("deposit", function () {
        it("Should deposit tokens and return shares", async function () {
            const { hederaVault, owner, stakingToken, sharesToken } = await deployFixture();
            const amountToDeposit = 170;

            console.log("Preview deposit ", await hederaVault.previewDeposit(amountToDeposit));

            await stakingToken.approve(hederaVault.target, amountToDeposit);

            const tx = await hederaVault.connect(owner).deposit(
                amountToDeposit,
                owner.address,
                { gasLimit: 3000000 }
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
                sharesToken,
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
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Deposit")
                .withArgs(owner.address, owner.address, amountToDeposit, anyValue);

            await rewardToken.approve(hederaVault.target, rewardAmount);

            // Add reward
            const addRewardTx = await hederaVault.addReward(rewardTokenAddress, rewardAmount);
            console.log(addRewardTx.hash);

            const rewards = await hederaVault.getAllRewards(owner);
            console.log("Available Reward: ", rewards);

            // Check rewards greater than 0
            expect(
                rewards[0]
            ).to.be.gt(0);

            await stakingToken.approve(hederaVault.target, amountToDeposit);

            const secondDepositTx = await hederaVault.connect(owner).deposit(
                amountToDeposit,
                owner.address,
                { gasLimit: 3000000 }
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
            const { hederaVaultRevertCases, owner } = await deployFixture();
            const amountToDeposit = 0;

            await expect(
                hederaVaultRevertCases.connect(owner).deposit(amountToDeposit, owner.address)
            ).to.be.reverted;
        });
    });

    describe("withdraw", function () {
        it("Should withdraw tokens", async function () {
            const { hederaVault, owner, sharesToken, stakingToken, rewardToken } = await deployFixture();
            const amountToWithdraw = 10;

            console.log("Preview Withdraw ", await hederaVault.previewWithdraw(amountToWithdraw));

            const currentReward = await hederaVault.getUserReward(owner.address, rewardToken.target);

            await sharesToken.approve(hederaVault.target, amountToWithdraw);

            const tx = await hederaVault.withdraw(
                amountToWithdraw,
                owner.address,
                owner.address,
                { gasLimit: 3000000 }
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
                sharesToken,
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
    });

    describe("mint", function () {
        it("Should mint tokens", async function () {
            const { hederaVault, owner, stakingToken, sharesToken } = await deployFixture();
            const amountOfShares = 1;

            const amount = await hederaVault.previewMint(amountOfShares);
            console.log("Preview Mint ", amount);

            await stakingToken.approve(hederaVault.target, amount);

            const tx = await hederaVault.connect(owner).mint(
                amountOfShares,
                owner.address,
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Deposit")
                .withArgs(owner.address, owner.address, anyValue, amountOfShares);

            // Check share token was transferred to user
            await expect(
                tx
            ).to.changeTokenBalance(
                sharesToken,
                hederaVault,
                amountOfShares
            );
        });
    });

    describe("addReward", function () {
        it("Should add reward to the Vault", async function () {
            const { hederaVault, rewardToken } = await deployFixture();
            const rewardAmount = 100000;

            await rewardToken.approve(hederaVault.target, rewardAmount);

            const tx = await hederaVault.addReward(
                rewardToken.target,
                rewardAmount,
                { gasLimit: 3000000 }
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
                hederaVault,
                rewardAmount
            );
        });

        it("Should revert if amount is zero", async function () {
            const { hederaVault, rewardToken } = await deployFixture();
            const rewardAmount = 0;

            const tx = await hederaVault.addReward(
                rewardToken.target,
                rewardAmount,
                { gasLimit: 3000000 }
            );

            await expect(
                tx
            ).to.be.reverted
        });

        it("Should revert if reward token is staking token", async function () {
            const { hederaVault, stakingToken } = await deployFixture();
            const rewardAmount = 10;

            const tx = await hederaVault.addReward(
                stakingToken.target,
                rewardAmount,
                { gasLimit: 3000000 }
            );

            await expect(
                tx
            ).to.be.reverted
        });

        it("Should revert if no token staked yet", async function () {
            const { hederaVaultRevertCases, rewardToken } = await deployFixture();
            const rewardAmount = 10;

            const tx = await hederaVaultRevertCases.addReward(
                rewardToken.target,
                rewardAmount,
                { gasLimit: 3000000 }
            );

            await expect(
                tx
            ).to.be.reverted
        });
    });

    describe("redeem", function () {
        it("Should redeem tokens", async function () {
            const { hederaVault, owner, sharesToken } = await deployFixture();
            const amountOfShares = 1;

            const tokensAmount = await hederaVault.previewRedeem(amountOfShares);
            console.log("Preview redeem ", tokensAmount);

            await sharesToken.approve(hederaVault.target, amountOfShares);

            const tx = await hederaVault.connect(owner).redeem(
                amountOfShares,
                owner.address,
                owner.address,
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Withdraw")
                .withArgs(owner.address, owner.address, tokensAmount, amountOfShares);
        });

        it("Should revert if zero assets", async function () {
            const { hederaVaultRevertCases, owner } = await deployFixture();
            const amountToReedem = 0;

            console.log(await hederaVaultRevertCases.previewRedeem(amountToReedem));

            await expect(
                hederaVaultRevertCases.connect(owner).redeem(
                    amountToReedem,
                    owner.address,
                    owner.address,
                    { gasLimit: 3000000 }
                )
            ).to.be.reverted;
        });
    });
});
