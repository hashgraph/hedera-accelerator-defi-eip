import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import { Client, AccountId, PrivateKey, ContractCallQuery, ContractFunctionParameters } from "@hashgraph/sdk";
import { Contract } from "ethers";
import abi from "@pythnetwork/pyth-sdk-solidity/abis/MockPyth.json";

dotenv.config();

const mockPyth = "0x330C40b17607572cf113973b8748fD1aEd742943";

async function createPriceFeedData(
    id: any,
    price: number,
    conf: number,
    expo: number,
    publishTime: number,
    emaPrice: number,
    emaConf: number,
    emaExpo: number,
    emaPublishTime: number,
    prevPublishTime: number
): Promise<string | null> {
    const types = [
        "bytes32",                   // id
        "int64",                     // price.price
        "uint64",                    // price.conf
        "int32",                     // price.expo
        "uint64",                    // price.publishTime
        "int64",                     // emaPrice.price
        "uint64",                    // emaPrice.conf
        "int32",                     // emaPrice.expo
        "uint64",                    // emaPrice.publishTime
        "uint64"                     // prevPublishTime
    ];

    const values = [
        id,             // id
        price,          // price.price
        conf,           // price.conf
        expo,           // price.expo
        publishTime,    // price.publishTime
        emaPrice,       // emaPrice.price
        emaConf,        // emaPrice.conf
        emaExpo,        // emaPrice.expo
        emaPublishTime, // emaPrice.publishTime
        prevPublishTime // prevPublishTime
    ];

    return ethers.AbiCoder.defaultAbiCoder().encode(types, values);
}

async function main() {
    const [deployer] = await ethers.getSigners();
    let client = Client.forTestnet();

    const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
    const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

    client.setOperator(
        operatorAccountId,
        operatorPrKey
    );

    const id = ethers.randomBytes(32);

    console.log(ethers.hexlify(id));

    const priceFeed = await createPriceFeedData(
        id,
        1500000,
        2000,
        -5,            // price.expo
        1698675600,    // price.publishTime
        1480000,       // emaPrice.price
        1800,          // emaPrice.conf
        -8,            // emaPrice.expo
        1698675600,    // emaPrice.publishTime
        1698672000
    );

    const pyth = await ethers.getContractAt(abi, mockPyth);
    const tx = await pyth.updatePriceFeeds([priceFeed]);

    console.log(tx.hash);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
