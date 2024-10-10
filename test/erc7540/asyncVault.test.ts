import { anyValue, ethers, expect } from "../setup";
import { TokenTransfer, createFungibleToken, TokenBalance, createAccount, addToken, mintToken } from "../../scripts/utils";
import { PrivateKey, Client, AccountId, TokenAssociateTransaction, AccountBalanceQuery } from "@hashgraph/sdk";
import hre from "hardhat";

// constants

const stakingTokenId = "0.0.4970021";
const vaultAddress = "0xA67538C178C8D40841B3556ef3E6BD37b01556F9"
const rewardTokenId = "0.0.4969978";
const rewardTokenAddress = "0x00000000000000000000000000000000004bd5fa";
const sharesTokenAddress = "0x00000000000000000000000000000000004bd632";
const sharesTokenId = "0.0.4970034";

// Tests
describe("AsyncVault", function () {
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
        //     .setTokenIds([sharesTokenId])
        //     .execute(client);

        // const stakingTokenAssociate = await new TokenAssociateTransaction()
        //     .setAccountId(operatorAccountId)
        //     .setTokenIds([newStakingTokenId])
        //     .execute(client);

        // const rewardTokenAssociate = await new TokenAssociateTransaction()
        //     .setAccountId(operatorAccountId)
        //     .setTokenIds([newRewardTokenId])
        //     .execute(client);

        const asyncVault = await ethers.getContractAt(
            "AsyncVault",
            vaultAddress
        );

        const rewardToken = await ethers.getContractAt(
            erc20.abi,
            rewardTokenAddress
        );

        const stakingToken = await ethers.getContractAt(
            erc20.abi,
            await asyncVault.asset()
        );

        const sharesToken = await ethers.getContractAt(
            erc20.abi,
            sharesTokenAddress
        );

        return {
            asyncVault,
            rewardToken,
            stakingToken,
            sharesToken,
            client,
            owner,
        };
    }

    describe("requestDeposit", function () {
        it("Should create async deposit request", async function () {
            const { asyncVault, owner, stakingToken, } = await deployFixture();
            const amountToDeposit = 1000;

            await stakingToken.approve(asyncVault.target, amountToDeposit);

            const requestDepositTx = await asyncVault.requestDeposit(
                amountToDeposit,
                owner.address,
                owner.address,
            );

            console.log(requestDepositTx.hash);

            await expect(
                requestDepositTx
            ).to.emit(asyncVault, "DepositRequested")
                .withArgs(owner.address, owner.address, anyValue, owner.address, amountToDeposit);
        });
    });

    describe("claimDeposit", function () {
        it("Should claim existed deposit request", async function () {
            const { asyncVault, owner } = await deployFixture();

            const claimDepositTx = await asyncVault.claimDeposit(
                owner.address,
                1,
                { gasLimit: 3000000 }
            );

            console.log(claimDepositTx.hash);

            await expect(
                claimDepositTx
            ).to.emit(asyncVault, "ClaimDeposit")
                .withArgs(1, owner.address, owner.address, 1000, anyValue);
        });
    });

    describe("requestRedeem", function () {
        it("Should redeem tokens", async function () {
            const { asyncVault, owner, sharesToken } = await deployFixture();
            const amountToRedeem = 1000;

            await sharesToken.approve(asyncVault.target, amountToRedeem);

            const requestRedeemTx = asyncVault.requestRedeem(amountToRedeem, owner.address, owner.address);
            await expect(
                requestRedeemTx
            ).to.emit(asyncVault, "RedeemRequested")
                .withArgs(owner.address, owner.address, anyValue, owner.address, amountToRedeem);
        });
    });

    describe("claimRedeem", function () {
        it.only("Should claim existed redeem request", async function () {
            const { asyncVault, owner } = await deployFixture();

            const claimDepositTx = await asyncVault.claimDeposit(
                owner.address,
                1,
                { gasLimit: 3000000 }
            );

            console.log(claimDepositTx.hash);

            await expect(
                claimDepositTx
            ).to.emit(asyncVault, "ClaimRedeem")
                .withArgs(1, owner.address, owner.address, anyValue, 500);
        });
    });

    describe("decreaseDepositRequest", function () {
        it("Should create async deposit ", async function () {
            const { asyncVault, owner, stakingToken, } = await deployFixture();
            const amountToDecrease = 1000;

            const decreaseDepositRequestTx = await asyncVault.decreaseDepositRequest(
                amountToDecrease,
                1,
            );

            console.log(decreaseDepositRequestTx.hash);

            await expect(
                decreaseDepositRequestTx
            ).to.emit(asyncVault, "DecreaseDepositRequest")
                .withArgs(1, owner.address, anyValue, anyValue);
        });
    });

    describe("addReward", function () {
        it("Should add reward to the Vault", async function () {
            const { asyncVault, rewardToken } = await deployFixture();
            const rewardAmount = 100000;

            await rewardToken.approve(asyncVault.target, rewardAmount);

            const tx = await asyncVault.addReward(
                rewardToken.target,
                rewardAmount,
                { gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(asyncVault, "RewardAdded")
                .withArgs(await rewardToken.getAddress(), rewardAmount);
        });
    });
});
