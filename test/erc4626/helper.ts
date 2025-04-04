import { AddressLike } from "ethers";
import { ethers } from "../setup";

// constants
export enum VaultType {
    Basic,
    Async
}

const cliff = 100;

export async function getCorrectDepositNumber(vault: any) {
    for (let i = 1; i > 0; i++) {
        if (await vault.previewDeposit(i) != 0) {
            return i;
        }
    }
}

export async function deployBasicVault(
    stakingToken: AddressLike,
    owner: AddressLike,
    feeConfig: any,
    unlockDuration: number
) {
    const BasicVault = await ethers.getContractFactory("BasicVault");
    const vault = await BasicVault.deploy(
        stakingToken,
        "TST",
        "TST",
        feeConfig,
        owner,
        owner,
        cliff,
        unlockDuration
    );
    await vault.waitForDeployment();
    return vault;
}

export async function deployAsyncVault(
    stakingToken: AddressLike,
    owner: AddressLike,
    feeConfig: any,
    unlockDuration: number
) {
    const AsyncVault = await ethers.getContractFactory("AsyncVault");
    const asyncVault = await AsyncVault.deploy(
        stakingToken,
        "AsyncTST",
        "AsyncTST",
        feeConfig,
        owner,
        owner,
        cliff,
        unlockDuration
    );
    await asyncVault.waitForDeployment();
    return asyncVault;
}

module.exports = {
    VaultType,
    getCorrectDepositNumber,
    deployBasicVault,
    deployAsyncVault
}
