import { Contract, LogDescription, Result, } from 'ethers';
import { expect, ethers, upgrades } from '../setup';
import { loadFixture, mine } from '@nomicfoundation/hardhat-network-helpers';
import * as ERC721MetadataABI from '../../data/abis/ERC721Metadata.json';
import { BuildingGovernance } from '../../typechain-types';

async function deployFixture() {
  const [owner, notOwner, voter1, voter2, voter3] = await ethers.getSigners();

  const uniswapRouter = await ethers.deployContract('UniswapRouterMock', []);
  const uniswapRouterAddress = await uniswapRouter.getAddress();
  const uniswapFactory = await ethers.deployContract('UniswapFactoryMock', []);
  const uniswapFactoryAddress = await uniswapFactory.getAddress();

  const tokenA = await ethers.deployContract('ERC20Mock', ["Token A", "TKA", 18]);
  const usdc = await ethers.deployContract('ERC20Mock', ["Token B", "TkB", 6]); // USDC

  await tokenA.waitForDeployment();
  await usdc.waitForDeployment();
  const tokenAAddress = await tokenA.getAddress();
  const usdcAddress = await usdc.getAddress();

  // create the NFT separately because ERC721Metadata is too large
  // must transfer ownership to BuildingFactory
  const nftCollectionFactory = await ethers.getContractFactory('ERC721Metadata', owner);
  const nftCollection = await nftCollectionFactory.deploy("Building NFT", "BILDNFT",);
  await nftCollection.waitForDeployment();
  const nftCollectionAddress = await nftCollection.getAddress();

  const identityImplementation = await ethers.deployContract('Identity', [owner.address, true], owner);
  const identityImplementationAuthority = await ethers.deployContract('ImplementationAuthority', [await identityImplementation.getAddress()], owner);
  const identityFactory = await ethers.deployContract('IdFactory', [await identityImplementationAuthority.getAddress()], owner);
  const identityGateway = await ethers.deployContract('IdentityGateway', [await identityFactory.getAddress(), []], owner);
  const identityGatewayAddress = await identityGateway.getAddress();

  // Beacon Upgradable Patter for Building
  const buildingImplementation = await ethers.deployContract('Building');
  const buildingImplementationAddress = await buildingImplementation.getAddress();

  const buildingBeaconFactory = await ethers.getContractFactory('BuildingBeacon');
  const buildingBeacon = await buildingBeaconFactory.deploy(buildingImplementationAddress)
  await buildingBeacon.waitForDeployment();
  const buildingBeaconAddress = await buildingBeacon.getAddress();

  // Beacon Upgradable Pattern for Treasury
  const treasuryImplementation = await ethers.deployContract('Treasury');
  const treasuryImplementationAddress = await treasuryImplementation.getAddress();
  const treasuryBeaconFactory = await ethers.getContractFactory('TreasuryBeacon');
  const treasuryBeacon = await treasuryBeaconFactory.deploy(treasuryImplementationAddress)
  await treasuryBeacon.waitForDeployment();
  const treasuryBeaconAddress = await treasuryBeacon.getAddress();

  // Beacon Upgradable Pattern for Treasury
  const governanceImplementation = await ethers.deployContract('BuildingGovernance');
  const governanceImplementationAddress = await governanceImplementation.getAddress();
  const governanceBeaconFactory = await ethers.getContractFactory('BuildingGovernanceBeacon');
  const governanceBeacon = await governanceBeaconFactory.deploy(governanceImplementationAddress)
  await governanceBeacon.waitForDeployment();
  const governanceBeaconAddress = await governanceBeacon.getAddress();

  const libraries = {
    "BuildingTokenLib" : await (await (await ethers.deployContract("BuildingTokenLib")).waitForDeployment()).getAddress(),
    "BuildingGovernanceLib" : await (await (await ethers.deployContract("BuildingGovernanceLib")).waitForDeployment()).getAddress(),
    "BuildingTreasuryLib" : await (await (await ethers.deployContract("BuildingTreasuryLib")).waitForDeployment()).getAddress(),
    "BuildingVaultLib" : await (await (await ethers.deployContract("BuildingVaultLib")).waitForDeployment()).getAddress(),
    "BuildingAutoCompounderLib" : await (await (await ethers.deployContract("BuildingAutoCompounderLib")).waitForDeployment()).getAddress(),
  }

  // Deploy BuildingFactory
  const buildingFactoryFactory = await ethers.getContractFactory('BuildingFactory', { libraries } );
  const buildingFactoryBeacon = await upgrades.deployBeacon(buildingFactoryFactory, { unsafeAllowLinkedLibraries: true });

  // TREX SUITE ------------------------------------
  const claimTopicsRegistryImplementation = await ethers.deployContract('ClaimTopicsRegistry', owner);
  const trustedIssuersRegistryImplementation = await ethers.deployContract('TrustedIssuersRegistry', owner);
  const identityRegistryStorageImplementation = await ethers.deployContract('IdentityRegistryStorage', owner);
  const identityRegistryImplementation = await ethers.deployContract('IdentityRegistry', owner);
  const modularComplianceImplementation = await ethers.deployContract('ModularCompliance', owner);
  const tokenImplementation = await ethers.deployContract('Token', owner);
  const trexImplementationAuthority = await ethers.deployContract('TREXImplementationAuthority',[true, ethers.ZeroAddress, ethers.ZeroAddress], owner);
  
  const versionStruct = {
    major: 4,
    minor: 0,
    patch: 0,
  };

  const contractsStruct = {
    tokenImplementation: await tokenImplementation.getAddress(),
    ctrImplementation: await claimTopicsRegistryImplementation.getAddress(),
    irImplementation: await identityRegistryImplementation.getAddress(),
    irsImplementation: await identityRegistryStorageImplementation.getAddress(),
    tirImplementation: await trustedIssuersRegistryImplementation.getAddress(),
    mcImplementation: await modularComplianceImplementation.getAddress(),
  };

  await trexImplementationAuthority.connect(owner).addAndUseTREXVersion(versionStruct, contractsStruct);

  const trexFactory = await ethers.deployContract('TREXFactory', [await trexImplementationAuthority.getAddress(), await identityFactory.getAddress()], owner);
  
  await identityFactory.connect(owner).addTokenFactory(await trexFactory.getAddress());
  const trexGateway = await ethers.deployContract('TREXGateway', [await trexFactory.getAddress(), true], owner);
  await trexFactory.transferOwnership(await trexGateway.getAddress());

  const trexGatewayAddress = await trexGateway.getAddress();
  const trexFactoryAddress = await trexFactory.getAddress();

  // ------------------------------------------------------

  // identityGateway must be the Owner of the IdFactory
  await identityFactory.transferOwnership(identityGatewayAddress);

  const buildingFactory = await upgrades.deployBeaconProxy(
    await buildingFactoryBeacon.getAddress(),
    buildingFactoryFactory,
    [
      nftCollectionAddress, 
      uniswapRouterAddress, 
      uniswapFactoryAddress,
      identityGatewayAddress,
      trexGatewayAddress,
      usdcAddress,
      buildingBeaconAddress,
      treasuryBeaconAddress,
      governanceBeaconAddress
    ],
    { 
      initializer: 'initialize',
    }, 
  );

  await buildingFactory.waitForDeployment();
  const buildingFactoryAddress = await buildingFactory.getAddress()

  await nftCollection.transferOwnership(buildingFactoryAddress);
  await trexGateway.addDeployer(buildingFactoryAddress);

  return {
    owner,
    notOwner,
    buildingFactory,
    buildingFactoryBeacon,
    tokenA,
    tokenAAddress,
    usdc,
    usdcAddress,
    nftCollection,
    nftCollectionAddress,
    uniswapRouterAddress,
    uniswapFactoryAddress,
    identityFactory,
    identityGateway,
    trexFactoryAddress,
    trexGatewayAddress,
    voter1,
    voter2,
    voter3,
    libraries,
  }
}

// get ERC721Metadata NFT collection deployed on contract deployment
async function getDeployedBuilding(buildingFactory: Contract, blockNumber: number): Promise<Array<string>> {
  // Decode the event using queryFilter
  const logs = await buildingFactory.queryFilter(buildingFactory.filters.NewBuilding, blockNumber, blockNumber);

  // Ensure one event was emitted
  expect(logs.length).to.equal(1);

  // Decode the log using the contract's interface
  const event = logs[0]; // Get the first log
  const decodedEvent = buildingFactory.interface.parseLog(event) as LogDescription;

  // Extract and verify the emitted address
  return Array.from(decodedEvent.args);
}

async function getProposalId(governance: BuildingGovernance, blockNumber: number) {
  // Decode the event using queryFilter
  const logs = await governance.queryFilter(governance.filters.ProposalCreated, blockNumber, blockNumber);

  // Decode the log using the contract's interface  
  const decodedEvent = governance.interface.parseLog(logs[0]) as LogDescription; // Get the first log

  // Extract and verify the emitted address  
  return decodedEvent.args[0]; 
}

describe('BuildingFactory', () => {
  describe('upgrade', () => {
    it('should be uprgradable', async () => {
      const { 
        buildingFactory,
        buildingFactoryBeacon,
        libraries,
       } = await loadFixture(deployFixture);

      const previousBuildingFactoryAddress = await buildingFactory.getAddress();
      const v2contractFactory = await ethers.getContractFactory('BuildingFactoryMock', { libraries });
      await upgrades.upgradeBeacon(await buildingFactoryBeacon.getAddress(), v2contractFactory, { unsafeAllowLinkedLibraries: true });

      const upgradedBuildinFactory = await ethers.getContractAt('BuildingFactoryMock', previousBuildingFactoryAddress);

      expect(await upgradedBuildinFactory.getAddress()).to.be.hexEqual(previousBuildingFactoryAddress);
      expect(await upgradedBuildinFactory.version()).to.be.equal('2.0');
    });
  });

  describe('.newBuilding()', () => {    
    it.only('should create a building', async () => {
      const { 
        owner,
        usdcAddress,
        buildingFactory, 
        uniswapFactoryAddress, 
        uniswapRouterAddress, 
        nftCollection,
        identityFactory
      } = await loadFixture(deployFixture);

      const buildingDetails = {
        tokenURI: 'ipfs://bafkreifuy6zkjpyqu5ygirxhejoryt6i4orzjynn6fawbzsuzofpdgqscq', 
        tokenName: 'MyToken', 
        tokenSymbol: 'MYT', 
        tokenDecimals: 18n,
        tokenMintAmount: ethers.parseEther('1000'),
        treasuryNPercent: 2000n, 
        treasuryReserveAmount: ethers.parseEther('1000'),
        governanceName : 'MyGovernance',
        vaultShareTokenName: 'Vault Token Name',
        vaultShareTokenSymbol: 'VTS',
        vaultFeeReceiver: owner,
        vaultFeeToken: usdcAddress,
        vaultFeePercentage: 2000,
        vaultCliff: 0n,
        vaultUnlockDuration: 0n,
        aTokenName: "AutoCompounder Token Name",
        aTokenSymbol: "ACTS"
      }

      const tx = await buildingFactory.newBuilding(buildingDetails);
      await tx.wait();
      
      const [buildingAddress] = await getDeployedBuilding(buildingFactory, tx.blockNumber as number);
      
      const building = await ethers.getContractAt('Building', buildingAddress);
      
      expect(await building.getAddress()).to.be.properAddress;
      expect(await nftCollection.ownerOf(0)).to.be.equal(await building.getAddress());
      expect(await nftCollection.tokenURI(0)).to.be.equal(buildingDetails.tokenURI);
      expect(await building.getUniswapFactory()).to.be.hexEqual(uniswapFactoryAddress);
      expect(await building.getUniswapRouter()).to.be.hexEqual(uniswapRouterAddress);
      
      const [firstBuilding] = await buildingFactory.getBuildingList();
      
      expect(firstBuilding[0]).to.be.hexEqual(await building.getAddress());
      expect(firstBuilding[1]).to.be.equal(0n);
      expect(firstBuilding[2]).to.be.equal(buildingDetails.tokenURI);
      expect(firstBuilding[3]).to.be.properAddress;
      
      const firstBuildingDetails = await buildingFactory.getBuildingDetails(await building.getAddress());
      
      expect(firstBuildingDetails[0]).to.be.hexEqual(await building.getAddress());
      expect(firstBuildingDetails[1]).to.be.equal(0n);
      expect(firstBuildingDetails[2]).to.be.equal(buildingDetails.tokenURI);
      expect(firstBuildingDetails[3]).to.be.equal(firstBuilding[3]);

      const detailsBuildingAddress = firstBuilding[0];
      const detailsIdentityAddress = firstBuilding[3];
      const detailsTokenAddress = firstBuilding[4];
      
      await expect(tx).to.emit(identityFactory, 'WalletLinked').withArgs(detailsBuildingAddress, detailsIdentityAddress);

      // make sure tokens were minted to the sender
      const buildingToken = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20', detailsTokenAddress);
      expect(await buildingToken.balanceOf(owner)).to.be.equal(ethers.parseEther('1000'));
    });

  });

  describe('.callContract()', () => {
    describe('when VAlID building address', () => {
      describe('when contract IS whitelisted', () => {
        it('should call ERC721Metadata contract and set metadata', async () => {
          const { owner, usdcAddress, buildingFactory, nftCollection, nftCollectionAddress } = await loadFixture(deployFixture);
          const NFT_ID = 0;

          const buildingDetails = {
            tokenURI: 'ipfs://bafkreifuy6zkjpyqu5ygirxhejoryt6i4orzjynn6fawbzsuzofpdgqscq', 
            tokenName: 'MyToken', 
            tokenSymbol: 'MYT', 
            tokenDecimals: 18n,
            tokenMintAmount: ethers.parseEther('1000'),
            treasuryNPercent: 2000n, 
            treasuryReserveAmount: ethers.parseEther('1000'),
            governanceName : 'MyGovernance',
            vaultShareTokenName: 'Vault Token Name',
            vaultShareTokenSymbol: 'VTS',
            vaultFeeReceiver: owner,
            vaultFeeToken: usdcAddress,
            vaultFeePercentage: 2000,
            vaultCliff: 0n,
            vaultUnlockDuration: 0n,
            aTokenName: "AutoCompounder Token Name",
            aTokenSymbol: "ACTS"
          }
          const tx = await buildingFactory.newBuilding(buildingDetails);
          await tx.wait();
          
          const [buildingAddress] = await getDeployedBuilding(buildingFactory, tx.blockNumber as number);
          const building = await ethers.getContractAt('Building', buildingAddress);
  
          const ERC721MetadataIface = new ethers.Interface(ERC721MetadataABI.abi);
          const encodedMetadataFunctionData = ERC721MetadataIface.encodeFunctionData(
            "setMetadata(uint256,string[],string[])", // function selector
            [ // function parameters
              NFT_ID, 
              ["size", "type", "color", "city"], 
              ["8", "mp4", "blue", "denver"]
            ]
          );
          
          await building.callContract(nftCollectionAddress, encodedMetadataFunctionData);
          const metadata = await nftCollection["getMetadata(uint256)"](NFT_ID);

          expect(metadata[0][0]).to.be.equal('size')
          expect(metadata[0][1]).to.be.equal('8')

          expect(metadata[1][0]).to.be.equal('type')
          expect(metadata[1][1]).to.be.equal('mp4')

          expect(metadata[2][0]).to.be.equal('color')
          expect(metadata[2][1]).to.be.equal('blue')

          expect(metadata[3][0]).to.be.equal('city')
          expect(metadata[3][1]).to.be.equal('denver')
        });
      });
    });
  });

  describe('integration flows', () => {
    it('should create building suite (token, vault, treasury governance), create a payment proposal, execute payment proposal', async () => {
        const { buildingFactory, usdc, usdcAddress, owner, voter1, voter2, voter3 } = await loadFixture(deployFixture);

        // create building
        const buildingDetails = {
          tokenURI: 'ipfs://bafkreifuy6zkjpyqu5ygirxhejoryt6i4orzjynn6fawbzsuzofpdgqscq', 
          tokenName: 'MyToken', 
          tokenSymbol: 'MYT', 
          tokenDecimals: 18n,
          tokenMintAmount: ethers.parseEther('1000'),
          treasuryNPercent: 2000n, 
          treasuryReserveAmount: ethers.parseUnits('1000', 6),
          governanceName : 'MyGovernance',
          vaultShareTokenName: 'Vault Token Name',
          vaultShareTokenSymbol: 'VTS',
          vaultFeeReceiver: owner,
          vaultFeeToken: usdcAddress,
          vaultFeePercentage: 2000,
          vaultCliff: 0n,
          vaultUnlockDuration: 0n,
          aTokenName: "AutoCompounder Token Name",
          aTokenSymbol: "ACTS"
        }
  
        const buildingTx = await buildingFactory.newBuilding(buildingDetails);
        const [
          /*buildingAddress*/, 
          tokenAddress,
          treasuryAddress,
          vaultAddress,
          governanceAddress
        ] = await getDeployedBuilding(buildingFactory, buildingTx.blockNumber as number);

        // create building token
        const token = await ethers.getContractAt('BuildingERC20', tokenAddress);
        const treasury = await ethers.getContractAt('Treasury', treasuryAddress);
        const vault = await ethers.getContractAt('BasicVault', vaultAddress);
        const governance = await ethers.getContractAt('BuildingGovernance', governanceAddress);

        // mint tokens to voter to be delegated for governance voting
        const mintAmount = ethers.parseEther('1000');
        await token.mint(owner.address, mintAmount);
        await token.mint(voter1.address, mintAmount);
        await token.mint(voter2.address, mintAmount);
        await token.mint(voter3.address, mintAmount);
        await token.connect(voter1).delegate(voter1.address);
        await token.connect(voter2).delegate(voter2.address);
        await token.connect(voter3).delegate(voter3.address);

        // stake tokens to vault
        await token.approve(vaultAddress, mintAmount);
        await vault.deposit(mintAmount, owner.address);
        
        // deposit usdc funds to the treasury in order to make payments
        const fundingAmount = ethers.parseUnits('10000', 6);
        await usdc.mint(owner.address, fundingAmount);
        await usdc.approve(treasuryAddress, fundingAmount);
        await treasury.deposit(fundingAmount);
        
        // make sure calculations of excess sent to vault are correct
        const toBusiness = fundingAmount * buildingDetails.treasuryNPercent / 10000n;
        const excessAmount = fundingAmount - buildingDetails.treasuryReserveAmount - toBusiness;
        expect(await usdc.balanceOf(vaultAddress)).to.be.equal(excessAmount);

        // create govenrnace payment proposal
        const amount = ethers.parseUnits('500', 6); // 500 USDT
        const to = ethers.Wallet.createRandom();
        const description = "Proposal #1: Pay 500 dollars";
  
        // receiver at this moment should have 0 usdc balance
        expect(await usdc.balanceOf(to.address)).to.be.eq(ethers.parseUnits('0', 6));
  
        const tx1 = await governance.createPaymentProposal(amount, to.address, description);
        await tx1.wait();
  
        const proposalId = await getProposalId(governance, tx1.blockNumber as number);
  
        // cast votes
        const votingDelay = await governance.votingDelay();
        const votingPeriod = await governance.votingPeriod();        
        await mine(votingDelay) // wait voting delay to begin casting votes
        await governance.connect(voter1).castVote(proposalId, 1); // "for" vote.
        await governance.connect(voter2).castVote(proposalId, 1); // "for" vote.
        await governance.connect(voter3).castVote(proposalId, 1); // "for" vote.
        await mine(votingPeriod); // wait for proposal voting period 
  
        // execute proposal
        await governance.executePaymentProposal(proposalId);
  
        // receiver should have 500 usdc balance after payment executed; 
        expect(await usdc.balanceOf(to.address)).to.be.eq(ethers.parseUnits('500', 6));
    });
  });
});
