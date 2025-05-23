import { ethers } from 'hardhat';
import Deployments from '../../data/deployments/chain-296.json';

const assetsAmount = ethers.parseUnits("10", 18);

export async function deposit() {
    const [owner] = await ethers.getSigners();

    // const vault = await ethers.getContractAt('BasicVault', Deployments.vault.Vault);
    // const stakingToken = await ethers.getContractAt('VaultToken', Deployments.vault.StakingToken);

    // await stakingToken.approve(vault.target, assetsAmount);

    // const tx = await vault.deposit(assetsAmount, owner.address);
    // await tx.wait();

    const VaultFactory = await ethers.getContractFactory("AsyncVaultFactory");
    const vaultFactory = await VaultFactory.deploy();

    console.log(`Deposit tx: ${await vaultFactory.getAddress()}`);
}

deposit()
    .catch(console.error);

module.exports = {
    deposit
}
