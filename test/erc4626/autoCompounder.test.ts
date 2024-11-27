import { anyValue, ethers, expect } from "../setup";
import { PrivateKey, Client, AccountId, TokenAssociateTransaction, AccountBalanceQuery } from "@hashgraph/sdk";
import hre from "hardhat";

import {
    usdcAddress,
    uniswapRouterAddress,
    pythOracleAddress,
    pythUtilsAddress
} from "../../constants";

// constants
const deployedAutoCompounder = "0xf014b970414602df2b293ef4f2d6b6f306cf2c1d";

const rewardTokenId = "0.0.4310077";
const rewardTokenAddress = "0x0000000000000000000000000000000000423252";
const shareTokenAddress = "0x00000000000000000000000000000000004eb98f";
const shareTokenId = "0.0.5159311";
const aTokenAddress = "0x00000000000000000000000000000000004ebd78";
const aTokenId = "0.0.5160312";

// Tests
describe("AutoCompounder", function () {
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

        const sharesTokenAssociate = await new TokenAssociateTransaction()
            .setAccountId(operatorAccountId)
            .setTokenIds([shareTokenId])
            .execute(client);
        const aTokenAssociate = await new TokenAssociateTransaction()
            .setAccountId(operatorAccountId)
            .setTokenIds([aTokenId])
            .execute(client);

        const autoCompounder = await ethers.getContractAt(
            "AutoCompounder",
            deployedAutoCompounder
        );

        const stakingToken = await ethers.getContractAt(
            erc20.abi,
            await autoCompounder.asset()
        );

        const share = await ethers.getContractAt(
            erc20.abi,
            shareTokenAddress
        );

        const aToken = await ethers.getContractAt(
            erc20.abi,
            await autoCompounder.aToken()
        );

        // await TokenTransfer(newStakingTokenId, operatorAccountId, "0.0.3638358", 1000, client);

        // const stakingTokenOperatorBalance = await (
        //     await TokenBalance(operatorAccountId, client)
        // ).tokens!.get(newRewardTokenId);
        // console.log("Reward token balance: ", stakingTokenOperatorBalance.toString());

        // const tx = await rewardToken.approve(hederaVault.target, 100);

        // const rewTx = await hederaVault.addReward(rewardTokenAddress, 100, { gasLimit: 3000000 });

        return {
            autoCompounder,
            stakingToken,
            aToken,
            share,
            client,
            owner,
        };
    }

    describe("deposit", function () {
        it.only("Should deposit tokens and return shares", async function () {
            const { autoCompounder, stakingToken, owner } = await deployFixture();
            const amountToDeposit = 1004;

            await stakingToken.approve(autoCompounder.target, amountToDeposit);

            const tx = await autoCompounder.connect(owner).deposit(
                amountToDeposit!,
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounder, "Deposit")
                .withArgs(owner.address, amountToDeposit, anyValue);
        });

        it("Should revert in case of zero assets", async function () {
            const { autoCompounder, owner } = await deployFixture();
            const amountToDeposit = 0;

            const tx = await autoCompounder.connect(owner).deposit(
                amountToDeposit!,
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.be.revertedWith("AutoCompounder: Invalid assets amount");
        });
    });

    describe("withdraw", function () {
        it("Should withdraw tokens", async function () {
            const { autoCompounder, owner, share, aToken } = await deployFixture();
            const amountToWithdraw = 10;

            await aToken.approve(autoCompounder.target, 100);
            await share.approve(autoCompounder.target, 1000);

            const tx = await autoCompounder.withdraw(
                amountToWithdraw,
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounder, "Withdraw")
                .withArgs(owner.address, amountToWithdraw, anyValue);
        });

        it("Should revert in case of zero amount of aToken", async function () {
            const { autoCompounder } = await deployFixture();
            const amountToWithdraw = 0;

            const tx = await autoCompounder.withdraw(
                amountToWithdraw,
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.be.revertedWith("AutoCompounder: Invalid aToken amount");
        });
    });

    describe("claim", function () {
        it("Should claim reward and reinvest", async function () {
            const { autoCompounder } = await deployFixture();
            const amountToWithdraw = 10;

            const tx = await autoCompounder.claim(
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounder, "Claim")
                .withArgs(anyValue);
        });
    });
});
