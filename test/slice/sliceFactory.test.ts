import { ethers, expect } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";
import { ZeroAddress, ZeroHash } from "ethers";
import { SliceFactory } from "../../typechain-types";

import {
    usdcAddress,
    uniswapRouterAddress
} from "../../constants";

// constants
const salt = "testSalt";

const tokenName = "TST";
const metadataUri = "ipfs://bafybeibnsoufr2renqzsh347nrx54wcubt5lgkeivez63xvivplfwhtpym/m";

// Tests
describe("SliceFactory", function () {
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

        const SliceFactory = await ethers.getContractFactory("SliceFactory");
        const sliceFactory = await SliceFactory.deploy() as SliceFactory;
        await sliceFactory.waitForDeployment();

        return {
            sliceFactory,
            client,
            owner,
        };
    }

    describe("deploySlice", function () {
        it("Should deploy Slice and compare slice group", async function () {
            const { sliceFactory, owner } = await deployFixture();
            const sliceDetails = {
                uniswapRouter: uniswapRouterAddress,
                usdc: usdcAddress,
                name: tokenName,
                symbol: tokenName,
                metadataUri: metadataUri
            }

            // Deploy Slice
            const tx = await sliceFactory.deploySlice(
                salt,
                sliceDetails,
                { from: owner.address, gasLimit: 3000000 }
            );

            console.log(tx.hash);

            await expect(
                tx
            ).to.emit(sliceFactory, "SliceDeployed");
        });

        it("Should revert if uniswap router zero address", async function () {
            const { sliceFactory } = await deployFixture();
            const sliceDetails = {
                uniswapRouter: ZeroAddress,
                usdc: usdcAddress,
                name: tokenName,
                symbol: tokenName,
                metadataUri: metadataUri
            }

            await expect(
                sliceFactory.deploySlice(
                    salt,
                    sliceDetails
                )
            ).to.be.revertedWith("SliceFactory: Invalid Uniswap Router address");
        });

        it("Should revert if USDC zero address", async function () {
            const { sliceFactory } = await deployFixture();
            const sliceDetails = {
                uniswapRouter: uniswapRouterAddress,
                usdc: ZeroAddress,
                name: tokenName,
                symbol: tokenName,
                metadataUri: metadataUri
            }

            await expect(
                sliceFactory.deploySlice(
                    salt,
                    sliceDetails
                )
            ).to.be.revertedWith("SliceFactory: Invalid USDC address");
        });

        it("Should revert if metadata URI wasn't provided", async function () {
            const { sliceFactory } = await deployFixture();
            const sliceDetails = {
                uniswapRouter: uniswapRouterAddress,
                usdc: usdcAddress,
                name: tokenName,
                symbol: tokenName,
                metadataUri: ""
            }

            await expect(
                sliceFactory.deploySlice(
                    salt,
                    sliceDetails
                )
            ).to.be.revertedWith("SliceFactory: Invalid metadata URI");
        });
    });
});
