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

const newStakingTokenId = "0.0.4338257";
const newRewardTokenId = "0.0.5449";
const rewardTokenAddress = "0x0000000000000000000000000000000000001549";
const newSharesTokenAddress = "0x000000000000000000000000000000000041c440";
const newSharesTokenId = "0.0.4310080";
const newVaultId = "0.0.4229240";

const vaultEr = "0xEC0b1cddD6755954c7dcbc72FE381B76D92C3E4B";
// Tests
describe("Vault", function () {
    async function deployFixture() {
        const [
            owner,
        ] = await ethers.getSigners();

        let client = Client.forTestnet();

        const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
        const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');
        const stAccountId = AccountId.fromString("0.0.2673429");

        client.setOperator(
            operatorAccountId,
            operatorPrKey
        );

        const erc20 = await hre.artifacts.readArtifact("contracts/erc4626/ERC20.sol:ERC20");

        // const sharesTokenAssociate = await new TokenAssociateTransaction()
        //     .setAccountId(operatorAccountId)
        //     .setTokenIds([newSharesTokenId])
        //     .execute(client);

        // const stakingTokenAssociate = await new TokenAssociateTransaction()
        //     .setAccountId(operatorAccountId)
        //     .setTokenIds([newStakingTokenId])
        //     .execute(client);

        // const rewardTokenAssociate = await new TokenAssociateTransaction()
        //     .setAccountId(operatorAccountId)
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
            newSharesTokenAddress
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
        it.only("Should deposit tokens and return shares", async function () {
            const { hederaVault, owner, stakingToken, rewardToken } = await deployFixture();
            const amountToDeposit = 1000;

            console.log("Preview deposit ", await hederaVault.previewDeposit(amountToDeposit!));

            // await rewardToken.approve(hederaVault.target, 10 * 1e8);

            // const tx = await hederaVault.addReward(rewardTokenAddress, 10 * 1e8, { gasLimit: 3000000 });
            // console.log(tx.hash);

            // console.log("TOTAL TOKENS", (await hederaVault.tokensRewardInfo(rewardTokenAddress)).amount);

            // console.log(await rewardToken.allowance(owner.address, hederaVault.target));

            // await stakingToken.approve(hederaVault.target, amountToDeposit);

            // const tx = await hederaVault.connect(owner).deposit(
            //     amountToDeposit!,
            //     owner.address,
            //     { gasLimit: 3000000 }
            // );

            // console.log(tx.hash);

            // await expect(
            //     tx
            // ).to.emit(hederaVault, "Deposit")
            //     .withArgs(owner.address, owner.address, amountToDeposit, anyValue);
            // await expect(
            //     tx
            // ).to.changeTokenBalance(rewardToken, "0xf5d7d351a5511a13de1f73d4882f88032a490a27", 1);
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
            const { hederaVault, owner, sharesToken } = await deployFixture();
            const amountToWithdraw = 1;

            console.log("Preview Withdraw ", await hederaVault.previewWithdraw(amountToWithdraw));

            await sharesToken.approve(hederaVault.target, amountToWithdraw)

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
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(hederaVault, "Deposit")
                .withArgs(owner.address, owner.address, anyValue, amountOfShares);
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
                .withArgs(await rewardToken.getAddress(), rewardAmount);
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
        // it("Should redeem tokens", async function () {
        //     const { hederaVault, owner, stakingToken, sharesToken } = await deployFixture();
        //     const amountOfShares = 1;

        //     const tokensAmount = await hederaVault.previewRedeem(amountOfShares);
        //     console.log("Preview redeem ", tokensAmount);

        //     console.log("TOTAL SUPPLY", await hederaVault.totalSupply());
        //     console.log("TOTAL ASSETS", await hederaVault.totalAssets());
        //     console.log("TOTAL TOKENS", await hederaVault.totalTokens());

        // await stakingToken.approve(hederaVault.target, amountOfShares);

        // const tx = await hederaVault.connect(owner).redeem(
        //     amountOfShares,
        //     owner.address,
        //     owner.address,
        //     { gasLimit: 3000000 }
        // );

        // console.log(tx.hash);

        // await expect(
        //     tx
        // ).to.emit(hederaVault, "Withdraw")
        //     .withArgs(owner.address, owner.address, tokensAmount, amountOfShares);
        // });

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
