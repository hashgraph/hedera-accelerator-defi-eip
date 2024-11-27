import { ethers, expect } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";

import {
    usdcAddress,
    uniswapRouterAddress
} from "../../constants";

// constants
const vault = "0xEC0b1cddD6755954c7dcbc72FE381B76D92C3E4B";

const deployedFactory = "0xdB21C090927E8b3Aa161CBda9a9B7662A5D1fe96";
const salt = "testSalt";
// Tests
describe("AutoCompounderFactory", function () {
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

        const autoCompounderFactory = await ethers.getContractAt(
            "AutoCompounderFactory",
            deployedFactory
        );

        return {
            autoCompounderFactory,
            client,
            owner,
        };
    }

    describe("deployAutoCompounder", function () {
        it("Should deploy AutoCompounder", async function () {
            const { autoCompounderFactory, owner } = await deployFixture();
            const autoCompounderDetails = {
                uniswapV2Router: uniswapRouterAddress,
                vault: vault,
                usdc: usdcAddress,
                aTokenName: "AToken",
                aTokenSymbol: "AToken"
            }

            const tx = await autoCompounderFactory.deployAutoCompounder(
                salt,
                autoCompounderDetails,
                { from: owner.address, gasLimit: 3000000, value: ethers.parseUnits("23", 18) }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(autoCompounderFactory, "AutoCompounderDeployed");
        });
    });
});
