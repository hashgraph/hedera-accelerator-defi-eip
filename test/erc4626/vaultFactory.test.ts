import { anyValue, ethers, expect } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";
import { ZeroAddress } from "ethers";
import { VaultFactory, VaultToken } from "../../typechain-types";

// constants
const salt = "testSalt";
const cliff = 100;
const unlockDuration = 500;

// Tests
describe("VaultFactory", function () {
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
        const stakingToken = await VaultToken.deploy(
            18
        ) as VaultToken;
        await stakingToken.waitForDeployment();

        const VaultFactory = await ethers.getContractFactory("VaultFactory");
        const vaultFactory = await VaultFactory.deploy() as VaultFactory;
        await vaultFactory.waitForDeployment();

        return {
            vaultFactory,
            stakingToken,
            client,
            owner,
        };
    }

    describe("deployVault", function () {
        it("Should deploy Vault", async function () {
            const { vaultFactory, stakingToken, owner } = await deployFixture();
            const vaultDetails = {
                stakingToken: stakingToken.target,
                shareTokenName: "TST",
                shareTokenSymbol: "TST",
                vaultRewardController: owner.address,
                feeConfigController: owner.address,
                cliff: cliff,
                unlockDuration: unlockDuration
            }

            const feeConfig = {
                receiver: ZeroAddress,
                token: ZeroAddress,
                feePercentage: 0
            }

            const tx = await vaultFactory.deployVault(
                salt,
                vaultDetails,
                feeConfig,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(vaultFactory, "VaultDeployed")
                .withArgs(anyValue, stakingToken.target, "TST", "TST");
        });
    });
});
