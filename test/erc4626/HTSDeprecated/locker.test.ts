import { ethers, expect, time } from "../../setup";
import { TokenTransfer, createFungibleToken, TokenBalance, createAccount, addToken, mintToken } from "../../../scripts/utils";
import { PrivateKey, Client, AccountId, TokenAssociateTransaction, AccountBalanceQuery } from "@hashgraph/sdk";
import erc20Abi from "../IERC20.json";
import { Locker } from "../../../typechain-types";
import { BigNumberish } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

// constants
const lockerAddress = "0x47cE9bbAeC2AFd351Dc08c0A8962b41037235C7d";

const stakingToken = "0x00000000000000000000000000000000004719e7";
const stakingTokenId = "0.0.4659687";
const rewardTokens = [
    "0x00000000000000000000000000000000004719e6",
    "0x0000000000000000000000000000000000476034",
    "0x0000000000000000000000000000000000476035"
];

const duration = 86400;

async function stake(
    locker: Locker,
    address: string,
    amount: BigNumberish,
) {
    const token = await ethers.getContractAt(
        erc20Abi.abi,
        address
    );

    await token.approve(locker.target, amount);

    return locker.stake(amount);
}
// Tests
describe("Locker", function () {
    async function deployFixture() {
        const [
            owner,
        ] = await ethers.getSigners();

        let client = Client.forTestnet();

        let aliceKey;
        let aliceAccountId;

        aliceKey = PrivateKey.generateED25519();
        aliceAccountId = await createAccount(client, aliceKey, 20);

        const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
        const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

        client.setOperator(
            operatorAccountId,
            operatorPrKey
        );

        const stakingTokenContract = await ethers.getContractAt(
            erc20Abi.abi,
            stakingToken
        );

        const locker = await ethers.getContractAt(
            "Locker",
            lockerAddress
        );

        client.setOperator(aliceAccountId!, aliceKey)

        await new TokenAssociateTransaction()
            .setAccountId(aliceAccountId!)
            .setTokenIds([stakingTokenId])
            .execute(client);

        client.setOperator(operatorAccountId, operatorPrKey);

        await TokenTransfer(stakingToken, operatorAccountId, aliceAccountId, 100, client);

        // const stakingTokenOperatorBalance = await (
        //     await TokenBalance(operatorAccountId, client)
        // ).tokens!.get(id);
        // console.log("Reward token balance: ", stakingTokenOperatorBalance.toString());

        return {
            locker,
            stakingTokenContract,
            aliceKey,
            aliceAccountId,
            client,
            owner,
        };
    }

    describe("stake", function () {
        it("Should stake the staking token", async function () {
            const { locker, owner, client } = await deployFixture();
            const amountToStake = ethers.parseUnits("1", 8);

            const tx = await stake(locker, stakingToken, amountToStake);

            await expect(
                tx
            ).to.emit(locker, "Staked")
                .withArgs(owner.address, stakingToken, amountToStake);
        });
    });

    describe("unlock", function () {
        it("Should unlock the staking token", async function () {
            const { locker, owner } = await deployFixture();
            const amountToStake = ethers.parseUnits("10", 8);

            await expect(
                stake(locker, stakingToken, amountToStake)
            ).to.emit(locker, "Staked")
                .withArgs(owner.address, stakingToken, amountToStake);

            await time.increase(duration);

            const tx = await locker.unlock(rewardTokens, amountToStake);

            await expect(
                tx
            ).to.emit(locker, "Withdraw")
                .withArgs(owner.address, stakingToken, amountToStake);

            await expect(
                tx
            ).to.changeTokenBalance(stakingToken, owner, amountToStake);

            console.log(tx.hash);
        });
    });

    describe("claimReward", function () {
        it("Should claim reward", async function () {
            const { locker, owner } = await deployFixture();
            const amountToStake = ethers.parseUnits("2", 18);

            await stake(locker, stakingToken, amountToStake);

            const rewardTokenContract = ethers.getContractAt(
                "TestToken",
                rewardTokens[0]
            );

            const tx = await locker.claimAllReward();

            await expect(
                tx
            ).to.emit(locker, "Claim")
                .withArgs(owner.address, rewardTokens[1], amountToStake);

            await expect(
                tx
            ).to.changeTokenBalance(rewardTokenContract, owner, amountToStake);
        });
    });

    describe("addReward", function () {
        it("Should add reward", async function () {
            const { locker, owner } = await deployFixture();
            const amountToAdd = ethers.parseUnits("50", 18);
            const amountToStake = ethers.parseUnits("1", 8);

            const tx = await stake(locker, stakingToken, amountToStake);

            await expect(
                tx
            ).to.emit(locker, "Staked")
                .withArgs(owner.address, stakingToken, amountToStake);

            const rewardTokenContract = await ethers.getContractAt(
                "TestToken",
                rewardTokens[0]
            );

            await rewardTokenContract.approve(locker.target, amountToAdd);

            await locker.addReward(rewardTokens[0], amountToAdd);
        });
    });
});
