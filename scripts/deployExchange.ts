import { ethers } from 'hardhat';

async function initDeployExchange() {
    const [deployer] = await ethers.getSigners();
    const oneSidedExchangeImplementation = await ethers.deployContract('OneSidedExchange', deployer);
    const exchangeAddress = await oneSidedExchangeImplementation.getAddress();

    console.log('Deployed:', exchangeAddress);
}

initDeployExchange();
