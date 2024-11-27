import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import { createFungibleToken, TokenTransfer } from "../scripts/utils";
import { Client, AccountId, PrivateKey } from "@hashgraph/sdk";
import { BytesLike, ZeroAddress } from "ethers";

import {
  usdcAddress,
  uniswapRouterAddress,
  pythOracleAddress,
  pythUtilsAddress
} from "../constants";

dotenv.config();

const rw1Token = "0x000000000000000000000000000000000044b66c";
const rw2Token = "0x000000000000000000000000000000000044b66e";
const rw1Id = ethers.keccak256(ethers.toUtf8Bytes("RT1"));
const rw2Id = ethers.keccak256(ethers.toUtf8Bytes("RT2"));

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();

  console.log("Deploying contract with account:", deployer.address, "at:", network.name);

  let client = Client.forTestnet();

  const operatorPrKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY || '');
  const operatorAccountId = AccountId.fromString(process.env.ACCOUNT_ID || '');

  client.setOperator(
    operatorAccountId,
    operatorPrKey
  );

  // const stakingToken = await createFungibleToken(
  //   "ERC4626 on Hedera",
  //   "HERC4626",
  //   process.env.ACCOUNT_ID,
  //   operatorPrKey.publicKey,
  //   client,
  //   operatorPrKey
  // );

  // const rewardToken = await createFungibleToken(
  //   "Reward Token 1",
  //   "RT2",
  //   process.env.ACCOUNT_ID,
  //   operatorPrKey.publicKey,
  //   client,
  //   operatorPrKey
  // );

  // console.log("Staking token addrress", "0x" + stakingToken!.toSolidityAddress());
  // console.log("Reward token addrress", "0x" + rewardToken!.toSolidityAddress());

  // Zero fee
  const feeConfig = {
    receiver: ZeroAddress,
    token: ZeroAddress,
    feePercentage: 0,
  };

  // const feeConfig = {
  //   receiver: "0x091b4a7ea614a3bd536f9b62ad5641829a1b174f",
  //   token: "0x" + stakingToken!.toSolidityAddress(),
  //   minAmount: 0,
  //   feePercentage: 1000,
  // };

  // const HederaVault = await ethers.getContractFactory("HederaVault");
  // const hederaVault = await HederaVault.deploy(
  //   "0x00000000000000000000000000000000004eb987",
  //   "TST",
  //   "TST",
  //   feeConfig,
  //   deployer.address,
  //   deployer.address,
  //   { from: deployer.address, gasLimit: 3000000, value: ethers.parseUnits("20", 18) }
  // );
  // console.log("Hash ", hederaVault.deploymentTransaction()?.hash);
  // await hederaVault.waitForDeployment();

  // console.log("Vault deployed with address: ", await hederaVault.getAddress());

  // const MockPyth = await ethers.getContractFactory("MockPyth");
  // const mockPyth = await MockPyth.deploy();
  // console.log("Hash ", mockPyth.deploymentTransaction()?.hash);
  // await mockPyth.waitForDeployment();

  // console.log("MockPyth deployed with address: ", await mockPyth.getAddress());

  // const PythUtils = await ethers.getContractFactory("@pythnetwork/pyth-sdk-solidity/PythUtils.sol:PythUtils");
  // const pythUtils = await PythUtils.deploy();
  // await pythUtils.waitForDeployment();

  // console.log("PythUtils deployed to:", await pythUtils.getAddress());

  // const VaultFactory = await ethers.getContractFactory("VaultFactory");
  // const vaultFactory = await VaultFactory.deploy();
  // console.log("Hash ", vaultFactory.deploymentTransaction()?.hash);
  // await vaultFactory.waitForDeployment();

  // console.log("Vault Factory deployed with address: ", await vaultFactory.getAddress());

  // const Locker = await ethers.getContractFactory("Locker");
  // const locker = await Locker.deploy(
  //   "0x00000000000000000000000000000000004719e7",
  //   [
  //     "0x00000000000000000000000000000000004719e6",
  //     "0x0000000000000000000000000000000000476034",
  //     "0x0000000000000000000000000000000000476035"
  //   ],
  //   { from: deployer.address, gasLimit: 15000000, value: ethers.parseUnits("12", 18) }
  // );
  // console.log("Hash ", locker.deploymentTransaction()?.hash);
  // await locker.waitForDeployment();

  // console.log("Locker deployed with address: ", await locker.getAddress());

  // const AsyncVault = await ethers.getContractFactory("AsyncVault");
  // const asyncVault = await AsyncVault.deploy(
  //   stakingTokenAddress,
  //   "TST",
  //   "TST",
  //   feeConfig,
  //   deployer.address,
  //   deployer.address,
  //   { from: deployer.address, gasLimit: 3000000, value: ethers.parseUnits("20", 18) }
  // );
  // console.log("Hash ", asyncVault.deploymentTransaction()?.hash);
  // await asyncVault.waitForDeployment();

  // console.log("AsyncVault deployed with address: ", await asyncVault.getAddress());

  // const TokenBalancer = await ethers.getContractFactory("TokenBalancer", {
  //   libraries: {
  //     PythUtils: "0x503187175Da79a0E62605D6CEC4e845E9ACC7C94"
  //   }
  // });
  // const tokenBalancer = await TokenBalancer.deploy(
  //   pythOracleAddress,
  //   uniswapRouterAddress,
  //   usdcAddress
  // );
  // console.log("Hash ", tokenBalancer.deploymentTransaction()?.hash);
  // await tokenBalancer.waitForDeployment();

  // console.log("Token Balancer deployed with address: ", await tokenBalancer.getAddress());

  const AutoCompounder = await ethers.getContractFactory("AutoCompounder");
  const autoCompounder = await AutoCompounder.deploy(
    uniswapRouterAddress,
    "0x1BFbfB870f0733200741dF3336f7b2abd2740207",
    usdcAddress,
    "aToken",
    "aToken",
    { from: deployer.address, gasLimit: 4000000, value: ethers.parseUnits("33", 18) }
  );
  console.log("Hash ", autoCompounder.deploymentTransaction()?.hash);
  await autoCompounder.waitForDeployment();

  console.log("AutoCompounder deployed with address: ", await autoCompounder.getAddress());

  const AutoCompounderFactory = await ethers.getContractFactory("AutoCompounderFactory");
  const autoCompounderFactory = await AutoCompounderFactory.deploy(
    { from: deployer.address, gasLimit: 4000000 }
  );
  console.log("Hash ", autoCompounderFactory.deploymentTransaction()?.hash);
  await autoCompounderFactory.waitForDeployment();

  console.log("AutoCompounder Factory deployed with address: ", await autoCompounderFactory.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
