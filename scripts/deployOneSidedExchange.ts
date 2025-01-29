import { ethers } from 'hardhat';

async function init() {
    const [deployer] = await ethers.getSigners();
    const oneSidedExchangeImplementation = await ethers.deployContract('OneSidedExchange', deployer);
    const exchangeAddress = await oneSidedExchangeImplementation.getAddress();

    console.log('OneSidedExchange address is:', exchangeAddress);
}

init();
