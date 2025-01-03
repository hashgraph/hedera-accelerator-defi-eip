import { ethers, expect } from "../setup";
import { PrivateKey, Client, AccountId } from "@hashgraph/sdk";
import { ZeroAddress } from "ethers";

import {
    usdcAddress,
    uniswapRouterAddress,
    pythOracleAddress,
    pythUtilsAddress
} from "../../constants";

// constants
const salt = "testSalt";

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

        const SliceFactory = await ethers.getContractFactory("SliceFactory", {
            libraries: {
                PythUtils: pythUtilsAddress,
            },
        });
        const sliceFactory = await SliceFactory.deploy();
        await sliceFactory.waitForDeployment();

        return {
            sliceFactory,
            client,
            owner,
        };
    }

    describe("deploySlice", function () {
        it("Should deploy Slice", async function () {
            const { sliceFactory, owner } = await deployFixture();
            const sliceDetails = {
                pyth: pythOracleAddress,
                uniswapRouter: uniswapRouterAddress,
                usdc: usdcAddress,
            }

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

        it("Should revert if oracle zero address", async function () {
            const { sliceFactory, owner } = await deployFixture();
            const sliceDetails = {
                pyth: ZeroAddress,
                uniswapRouter: uniswapRouterAddress,
                usdc: usdcAddress,
            }

            await expect(
                sliceFactory.deploySlice(
                    salt,
                    sliceDetails
                )
            ).to.be.revertedWith("SliceFactory: Invalid Pyth oracle address");
        });

        it("Should revert if uniswap router zero address", async function () {
            const { sliceFactory } = await deployFixture();
            const sliceDetails = {
                pyth: pythOracleAddress,
                uniswapRouter: ZeroAddress,
                usdc: usdcAddress,
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
                pyth: pythOracleAddress,
                uniswapRouter: uniswapRouterAddress,
                usdc: ZeroAddress,
            }

            await expect(
                sliceFactory.deploySlice(
                    salt,
                    sliceDetails
                )
            ).to.be.revertedWith("SliceFactory: Invalid USDC address");
        });
    });
});
