import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import { createFungibleToken, TokenTransfer } from "../scripts/utils";
import { Client, AccountId, PrivateKey } from "@hashgraph/sdk";
import { ZeroAddress } from "ethers";

dotenv.config();

const deployedOracle = "0xC48277F42d738A06B8bD6a61700aF35018Cf5AEc";
const deployedSaucerSwap = "0xACE99ADFd95015dDB33ef19DCE44fee613DB82C2";
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

  const stakingToken = await createFungibleToken(
    "ERC4626 on Hedera",
    "HERC4626",
    process.env.ACCOUNT_ID,
    operatorPrKey.publicKey,
    client,
    operatorPrKey
  );

  const rewardToken = await createFungibleToken(
    "Reward Token 1",
    "RT2",
    process.env.ACCOUNT_ID,
    operatorPrKey.publicKey,
    client,
    operatorPrKey
  );

  const stakingTokenAddress = "0x" + stakingToken!.toSolidityAddress();
  const rewardTokenAddress = "0x" + rewardToken!.toSolidityAddress();

  console.log("Staking token addrress", stakingTokenAddress);
  console.log("Reward token addrress", rewardTokenAddress);

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
  //   stakingTokenAddress,
  //   "TST",
  //   "TST",
  //   feeConfig,
  //   deployer.address,
  //   deployer.address,
  //   deployedOracle,
  //   deployedSaucerSwap,
  //   [rw1Token, rw2Token],
  //   [50000, 50000],
  //   [
  //     rw1Id,
  //     rw2Id
  //   ],
  //   { from: deployer.address, gasLimit: 3000000, value: ethers.parseUnits("16", 18) }
  // );
  // console.log("Hash ", hederaVault.deploymentTransaction()?.hash);
  // await hederaVault.waitForDeployment();

  // console.log("Vault deployed with address: ", await hederaVault.getAddress());

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

  const AsyncVault = await ethers.getContractFactory("AsyncVault");
  const asyncVault = await AsyncVault.deploy(
    stakingTokenAddress,
    "TST",
    "TST",
    feeConfig,
    deployer.address,
    deployer.address,
    { from: deployer.address, gasLimit: 3000000, value: ethers.parseUnits("20", 18) }
  );
  console.log("Hash ", asyncVault.deploymentTransaction()?.hash);
  await asyncVault.waitForDeployment();

  console.log("AsyncVault deployed with address: ", await asyncVault.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
