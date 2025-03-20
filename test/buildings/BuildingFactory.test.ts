import { Contract, LogDescription, } from 'ethers';
import { expect, ethers, upgrades } from '../setup';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import * as ERC721MetadataABI from '../../data/abis/ERC721Metadata.json';
import { usdcAddress } from '../../constants';

async function deployFixture() {
  const [owner, notOwner] = await ethers.getSigners();

  const uniswapRouter = await ethers.deployContract('UniswapRouterMock', []);
  const uniswapRouterAddress = await uniswapRouter.getAddress();
  const uniswapFactory = await ethers.deployContract('UniswapFactoryMock', []);
  const uniswapFactoryAddress = await uniswapFactory.getAddress();

  const tokenA = await ethers.deployContract('ERC20Mock', ["Token A", "TKA", 18]);
  const tokenB = await ethers.deployContract('ERC20Mock', ["Token B", "TkB", 6]); // USDC

  await tokenA.waitForDeployment();
  await tokenB.waitForDeployment();
  const tokenAAddress = await tokenA.getAddress();
  const tokenBAddress = await tokenB.getAddress();

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

  // Deploy BuildingFactory
  const buildingFactoryFactory = await ethers.getContractFactory('BuildingFactory', owner);
  const buildingFactoryBeacon = await upgrades.deployBeacon(buildingFactoryFactory);

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
  
  const vaultFactory = await ethers.deployContract('VaultFactory');
  const vaultFactoryAddress = await vaultFactory.getAddress();

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
      vaultFactoryAddress,
      treasuryBeaconAddress,
      governanceBeaconAddress
    ],
    { 
      initializer: 'initialize'
    }
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
    tokenB,
    tokenBAddress,
    nftCollection,
    nftCollectionAddress,
    uniswapRouterAddress,
    uniswapFactoryAddress,
    identityFactory,
    identityGateway,
    trexFactoryAddress,
    trexGatewayAddress,
    vaultFactory,
    vaultFactoryAddress
  }
}

// get ERC721Metadata NFT collection deployed on contract deployment
async function getDeployedBuilding(buildingFactory: Contract, blockNumber: number) {
  // Decode the event using queryFilter
  const logs = await buildingFactory.queryFilter(buildingFactory.filters['NewBuilding(address, address)'], blockNumber, blockNumber);

  // Ensure one event was emitted
  expect(logs.length).to.equal(1);

  // Decode the log using the contract's interface
  const event = logs[0]; // Get the first log
  const decodedEvent = buildingFactory.interface.parseLog(event) as LogDescription;

  // Extract and verify the emitted address
  const newBuildingAddress = decodedEvent.args[0]; // Assuming the address is the first argument
  return await ethers.getContractAt('Building', newBuildingAddress);
}

async function getDeployedToken(buildingFactory: Contract, blockNumber: number) {
  // Decode the event using queryFilter
  const logs = await buildingFactory.queryFilter(buildingFactory.filters['NewERC3643Token(address, address, address)'], blockNumber, blockNumber);

  // Ensure one event was emitted
  expect(logs.length).to.equal(1);

  // Decode the log using the contract's interface  
  const decodedEvent = buildingFactory.interface.parseLog(logs[0]) as LogDescription; // Get the first log

  // Extract and verify the emitted address  
  return await ethers.getContractAt('Token',  decodedEvent.args[0]); // Assuming the address is the first argument
}

async function getDeployedGovernance(buildingFactory: Contract, blockNumber: number) {
  // Decode the event using queryFilter
  const logs = await buildingFactory.queryFilter(buildingFactory.filters['NewGovernance(address, address, address)'], blockNumber, blockNumber);

  // Ensure one event was emitted
  expect(logs.length).to.equal(1);

  // Decode the log using the contract's interface  
  const decodedEvent = buildingFactory.interface.parseLog(logs[0]) as LogDescription; // Get the first log

  // Extract and verify the emitted address  
  return await ethers.getContractAt('BuildingGovernance',  decodedEvent.args[0]); // Assuming the address is the first argument
}

async function getDeployedTreasury(buildingFactory: Contract, blockNumber: number) {
  // Decode the event using queryFilter
  const logs = await buildingFactory.queryFilter(buildingFactory.filters['NewTreasury(address, address, address)'], blockNumber, blockNumber);

  // Ensure one event was emitted
  expect(logs.length).to.equal(1);

  // Decode the log using the contract's interface  
  const decodedEvent = buildingFactory.interface.parseLog(logs[0]) as LogDescription; // Get the first log

  // Extract and verify the emitted address  
  return await ethers.getContractAt('Treasury',  decodedEvent.args[0]); // Assuming the address is the first argument
}

describe('BuildingFactory', () => {
  describe('upgrade', () => {
    it('should be uprgradable', async () => {
      const { 
        buildingFactory,
        buildingFactoryBeacon
       } = await loadFixture(deployFixture);

      const previousBuildingFactoryAddress = await buildingFactory.getAddress();
      const v2contractFactory = await ethers.getContractFactory('BuildingFactoryMock');
      await upgrades.upgradeBeacon(await buildingFactoryBeacon.getAddress(), v2contractFactory);

      const upgradedBuildinFactory = await ethers.getContractAt('BuildingFactoryMock', previousBuildingFactoryAddress);

      expect(await upgradedBuildinFactory.getAddress()).to.be.hexEqual(previousBuildingFactoryAddress);
      expect(await upgradedBuildinFactory.version()).to.be.equal('2.0');
    });
  });


  describe('.newBuilding()', () => {    
    it('should create a building', async () => {
      const { 
        buildingFactory, 
        uniswapFactoryAddress, 
        uniswapRouterAddress, 
        nftCollection,
        identityFactory
      } = await loadFixture(deployFixture);

      const tokenURI = "ipfs://building-nft-uri";
      const tx = await buildingFactory.newBuilding(tokenURI);
      await tx.wait();
      
      const building  = await getDeployedBuilding(buildingFactory, tx.blockNumber as number);
      
      expect(await building.getAddress()).to.be.properAddress;
      expect(await nftCollection.ownerOf(0)).to.be.equal(await building.getAddress());
      expect(await nftCollection.tokenURI(0)).to.be.equal(tokenURI);
      expect(await building.getUniswapFactory()).to.be.hexEqual(uniswapFactoryAddress);
      expect(await building.getUniswapRouter()).to.be.hexEqual(uniswapRouterAddress);
      
      const [firstBuilding] = await buildingFactory.getBuildingList();
      
      expect(firstBuilding[0]).to.be.hexEqual(await building.getAddress());
      expect(firstBuilding[1]).to.be.equal(0n);
      expect(firstBuilding[2]).to.be.equal(tokenURI);
      expect(firstBuilding[3]).to.be.properAddress;
      
      const firstBuildingDetails = await buildingFactory.getBuildingDetails(await building.getAddress());
      
      expect(firstBuildingDetails[0]).to.be.hexEqual(await building.getAddress());
      expect(firstBuildingDetails[1]).to.be.equal(0n);
      expect(firstBuildingDetails[2]).to.be.equal(tokenURI);
      expect(firstBuildingDetails[3]).to.be.equal(firstBuilding[3]);

      const buildingAddress = firstBuilding[0];
      const identityAddress = firstBuilding[3];
      
      await expect(tx).to.emit(identityFactory, 'WalletLinked').withArgs(buildingAddress, identityAddress);
    });

  });

  describe('.callContract()', () => {
    describe('when VAlID building address', () => {
      describe('when contract IS whitelisted', () => {
        it('should call ERC721Metadata contract and set metadata', async () => {
          const { buildingFactory, nftCollection, nftCollectionAddress } = await loadFixture(deployFixture);
          const NFT_ID = 0;

          const tokenURI = "ipfs://building-nft-uri";
          const tx = await buildingFactory.newBuilding(tokenURI);
          await tx.wait();
          
          const building  = await getDeployedBuilding(buildingFactory, tx.blockNumber as number);
  
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

  describe('.newERC3643Building()', () => {
    describe('when building address is not valid', () => {
      it('should revert', async () => {
        const { 
          buildingFactory, 
         } = await loadFixture(deployFixture);

         await expect(buildingFactory.newERC3643Token(ethers.ZeroAddress, "token name", "TKN", 18))
          .to.be.revertedWith('BuildingFactory: Invalid building address');

          const randomWallet = ethers.Wallet.createRandom();

          await expect(buildingFactory.newERC3643Token(randomWallet.address, "token name", "TKN", 18))
          .to.be.revertedWith('BuildingFactory: Invalid building address');

      });
    });

    describe('when building address is valid', () => {
      it('should create token', async () => {
        const { 
          buildingFactory, 
          owner
         } = await loadFixture(deployFixture);

          const tx = await buildingFactory.newBuilding("ipfs://tokenuri");
          await tx.wait();
          
          const building  = await getDeployedBuilding(buildingFactory, tx.blockNumber as number);
          const buildingAddress = await building.getAddress();

         const tx2 = await buildingFactory.newERC3643Token(buildingAddress, "token name", "TKN", 18);
         await tx2.wait();

         const buildingDetails = await buildingFactory.getBuildingDetails(buildingAddress);
         const deployedToken = buildingDetails[4];

         expect(deployedToken).to.be.properAddress; // tokenAddress;
         await expect(tx2).to.emit(buildingFactory, 'NewERC3643Token').withArgs(deployedToken, buildingAddress, owner.address);
      });

      describe('when building already deployed', () => {
        it('shoud revert', async () => {
          const { 
            buildingFactory, 
           } = await loadFixture(deployFixture);
  
            const tx = await buildingFactory.newBuilding("ipfs://tokenuri");
            await tx.wait();
            
            const building  = await getDeployedBuilding(buildingFactory, tx.blockNumber as number);
            const buildingAddress = await building.getAddress();
  
           const tx2 = await buildingFactory.newERC3643Token(buildingAddress, "token name", "TKN", 18);
           await tx2.wait();

           await expect(buildingFactory.newERC3643Token(buildingAddress, "other name", "OTKN", 18))
            .to.be.revertedWith('BuildingFactory: token already created for building');
        });
      });
    });
  });

  describe('.newTreasury()', () => {
    describe('when building address is invalid', () => {
      it('should revert', async () => {
        const { buildingFactory } = await loadFixture(deployFixture);
        await expect(buildingFactory.newTreasury(ethers.ZeroAddress, ethers.ZeroAddress, 0, 0)).to.be.revertedWith('BuildingFactory: Invalid building address');
        await expect(buildingFactory.newTreasury(ethers.Wallet.createRandom().address, ethers.ZeroAddress, 0, 0)).to.be.revertedWith('BuildingFactory: Invalid building address');
      });
    });

    describe('when token address is invalid', () => {
      it('should revert', async () => {
        const { buildingFactory, owner } = await loadFixture(deployFixture);
        
        const buildingTx = await buildingFactory.newBuilding("ipfs:://anyurl");
        const building  = await getDeployedBuilding(buildingFactory, buildingTx.blockNumber as number);
        const buildingAddress = await building.getAddress();

        await expect(buildingFactory.newTreasury(buildingAddress, ethers.ZeroAddress, 0, 0)).to.be.revertedWith('BuildingFactory: Invalid token address');
        await expect(buildingFactory.newTreasury(buildingAddress, ethers.Wallet.createRandom().address, 0, 0)).to.be.revertedWith('BuildingFactory: Invalid token address');
      });
    });

    describe('when building and token addresses are valid', () => {
      it('should create treasury', async () => {
        const { buildingFactory, owner } = await loadFixture(deployFixture);

        const buildingTx = await buildingFactory.newBuilding("ipfs:://anyurl");
        const building  = await getDeployedBuilding(buildingFactory, buildingTx.blockNumber as number);
        const buildingAddress = await building.getAddress();

        const tokenTx = await buildingFactory.newERC3643Token(buildingAddress, "token name", "TKN", 18);
        await tokenTx.wait();

        const buildingDetails = await buildingFactory.getBuildingDetails(buildingAddress);
        const tokenAddress = buildingDetails.erc3643Token;

        const newTreasuryTx = await buildingFactory.newTreasury(buildingAddress, tokenAddress, 100, 100);
        await newTreasuryTx.wait();

        const buildingDetails2 = await buildingFactory.getBuildingDetails(buildingAddress);
        const treasuryAddress = buildingDetails2.treasury;
        
        expect(treasuryAddress).to.be.properAddress; // treasuryAddress;
        await expect(newTreasuryTx).to.emit(buildingFactory, 'NewTreasury').withArgs(treasuryAddress, buildingAddress, owner);
  
      });
    });
  });

  describe('.newGovernance()', () => {
    describe('when is valid building, token and treasury', () => {
      it('should create new governance', async () => {
        const { buildingFactory, owner } = await loadFixture(deployFixture);

        const buildingTx = await buildingFactory.newBuilding("ipfs:://anyurl");
        const building  = await getDeployedBuilding(buildingFactory, buildingTx.blockNumber as number);
        const buildingAddress = await building.getAddress();

        const tokenTx = await buildingFactory.newERC3643Token(buildingAddress, "Token Name", "Symbol", 18);
        const token = await getDeployedToken(buildingFactory, tokenTx.blockNumber as number);
        const tokenAddress = await token.getAddress();

        const treasuryTx = await buildingFactory.newTreasury(buildingAddress, tokenAddress, 100, 100)
        const treasury = await getDeployedTreasury(buildingFactory, treasuryTx.blockNumber as number);
        const treasuryAddress = await treasury.getAddress();

        const newGovernanceTx = await buildingFactory.newGovernance(buildingAddress, "New Governance", tokenAddress, treasuryAddress);
        const governance = await getDeployedGovernance(buildingFactory, newGovernanceTx.blockNumber as number);
        const governanceAdress = await governance.getAddress();

        const buildingDetails = await buildingFactory.getBuildingDetails(buildingAddress);
        
        expect(buildingDetails.governance).to.be.properAddress; // treasuryAddress;
        expect(governanceAdress).to.be.equal(buildingDetails.governance);
        await expect(newGovernanceTx).to.emit(buildingFactory, 'NewGovernance').withArgs(buildingDetails.governance, buildingAddress, owner);
      });
    });
  });
});
