import { ethers } from 'hardhat';
import Deployments from '../../../data/deployments/chain-296.json';
import { LogDescription } from 'ethers';
import { BuildingFactory } from '../../../typechain-types';

async function getDeployedBuilding(buildingFactory: BuildingFactory, blockNumber: number): Promise<unknown[]> {
  // Decode the event using queryFilter
  const logs = await buildingFactory.queryFilter(buildingFactory.filters.NewBuilding, blockNumber, blockNumber);
  // Decode the log using the contract's interface
  const event = logs[0]; // Get the first log
  const decodedEvent = buildingFactory.interface.parseLog(event) as LogDescription;

  // Extract and verify the emitted address
  return decodedEvent.args as unknown[];
}

async function createBuilding(): Promise<string> {
  const [owner] = await ethers.getSigners();
  const buildingFactory = await ethers.getContractAt(
    "BuildingFactory",
    Deployments.factories.BuildingFactory
  );

  const buildingDetails = {
    tokenURI: 'ipfs://bafkreifuy6zkjpyqu5ygirxhejoryt6i4orzjynn6fawbzsuzofpdgqscq', 
    tokenName: 'MyToken', 
    tokenSymbol: 'MYT', 
    tokenDecimals: 18n,
    treasuryNPercent: 2000n, 
    treasuryReserveAmount: ethers.parseUnits('1000', 6),
    governanceName : 'MyGovernance',
    vaultShareTokenName: 'Token Name',
    vaultShareTokenSymbol: 'Token Symbol',
    vaultFeeReceiver: owner.address,
    vaultFeeToken: ethers.Wallet.createRandom().address,
    vaultFeePercentage: 2_00n,
    vaultCliff: 0n,
    vaultUnlockDuration: 0n
  }
  const tx = await buildingFactory.newBuilding(buildingDetails, { gasLimit: 6_000_000});  
  await tx.wait();

  const [building, token, treasury, vault, governance] = await getDeployedBuilding(buildingFactory, tx.blockNumber as number);

  console.log("- tx sent with hash" + tx.hash);
  console.log("- created new building: ", building);
  console.log("- created new token: ", token);
  console.log("- created new treasury: ", treasury);
  console.log("- created new vault: ", vault);
  console.log("- created new governance: ", governance);

  await mintAndDelegateTokens(token as string);

  return building as string;
}

async function addLiquidity(buildingAddress: string) {
  const [owner] = await ethers.getSigners();
  const buildingFactory = await ethers.getContractAt('BuildingFactory', Deployments.factories.BuildingFactory);

  const building = await ethers.getContractAt('Building', buildingAddress);
  const buildingDetails = await buildingFactory.getBuildingDetails(buildingAddress);

  const buildingTokenAddress = buildingDetails.erc3643Token;
  const buildingToken = await ethers.getContractAt('BuildingERC20', buildingTokenAddress);
  const buildingTokenAmount = ethers.parseEther('1000');

  const usdc = await ethers.deployContract('BuildingERC20', ["USDC", "USDC", 6]);
  const usdcAmount = ethers.parseUnits('1', 6);
  const usdcAddress = await usdc.getAddress();
  
  const mintTx = await buildingToken.mint(owner.address, buildingTokenAmount, { gasLimit: 6000000 });
  await mintTx.wait()

  const usdcMintTx = await usdc.mint(owner.address, usdcAmount, { gasLimit: 6000000 });
  await usdcMintTx.wait()

  const appr1Tx = await buildingToken.approve(buildingAddress, buildingTokenAmount, { gasLimit: 6000000 });
  await appr1Tx.wait();
  const appr2Tx = await usdc.approve(buildingAddress, usdcAmount, { gasLimit: 6000000 });
  await appr2Tx.wait();
  
  const tx = await building.addLiquidity(buildingTokenAddress, buildingTokenAmount, usdcAddress, usdcAmount, { gasLimit: 6000000 });
  await tx.wait();

  console.log('- liquidity added ', tx.hash);
}

async function mintAndDelegateTokens(tokenAddress: string) {
  const [voter1, voter2, voter3] = await ethers.getSigners();

  const token = await ethers.getContractAt('BuildingERC20', tokenAddress);
  const mintAmount = ethers.parseEther('1000');

  const a = await token.mint(voter1.address, mintAmount, { gasLimit: 6000000 });
  const b = await token.mint(voter2.address, mintAmount, { gasLimit: 6000000 });
  const c = await token.mint(voter3.address, mintAmount, { gasLimit: 6000000 });

  await a.wait();
  await b.wait();
  await c.wait();

  console.log('- tokens minted');

  const d = await token.connect(voter1).delegate(voter1.address, { gasLimit: 6000000 });
  const e = await token.connect(voter2).delegate(voter2.address, { gasLimit: 6000000 });
  const f = await token.connect(voter3).delegate(voter3.address, { gasLimit: 6000000 });

  await d.wait();
  await e.wait();
  await f.wait();

  console.log('- votes delegated');
}


async function run () {
  await createBuilding();
}

run()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  });
