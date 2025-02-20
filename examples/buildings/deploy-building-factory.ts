import { ethers } from 'hardhat';
import { upgrades } from "../../test/setup";

async function deployFactoryBuilding() {

  const [owner] = await ethers.getSigners();

  const uniswapRouter = await ethers.deployContract('UniswapRouterMock', []);
  const uniswapRouterAddress = await uniswapRouter.getAddress();
  console.log("UniswapRouter deployed at:", uniswapRouterAddress);
  const uniswapFactory = await ethers.deployContract('UniswapFactoryMock', []);
  const uniswapFactoryAddress = await uniswapFactory.getAddress();
  console.log("UniswapFactory deployed at:", uniswapFactoryAddress);  

  // create the NFT separately because ERC721Metadata is too large
  // must transfer ownership to BuildingFactory
  const nftCollectionFactory = await ethers.getContractFactory('ERC721Metadata', owner);
  const nftCollection = await nftCollectionFactory.deploy("Building NFT", "BILDNFT",);
  await nftCollection.waitForDeployment();
  const nftCollectionAddress = await nftCollection.getAddress();
  console.log("NFT Collection deployed at:", nftCollectionAddress);

  const identityImplementation = await ethers.deployContract('Identity', [owner.address, true], owner);
  const identityImplementationAuthority = await ethers.deployContract('ImplementationAuthority', [await identityImplementation.getAddress()], owner);
  const identityFactory = await ethers.deployContract('IdFactory', [await identityImplementationAuthority.getAddress()], owner);
  const identityGateway = await ethers.deployContract('IdentityGateway', [await identityFactory.getAddress(), []], owner);
  const identityGatewayAddress = await identityGateway.getAddress();
  console.log("IdentityGateway deployed at:", identityGatewayAddress);  

  // Beacon Upgradable Patter for Building
  const buildingImplementation = await ethers.deployContract('Building');
  const buildingImplementationAddress = await buildingImplementation.getAddress();
  console.log("Building deployed at:", buildingImplementationAddress);

  const buildingBeaconFactory = await ethers.getContractFactory('BuildingBeacon');
  const buildingBeacon = await buildingBeaconFactory.deploy(buildingImplementationAddress)
  await buildingBeacon.waitForDeployment();
  const buildingBeaconAddress = await buildingBeacon.getAddress();
  console.log("BuildingBeacon deployed at:", buildingBeaconAddress);

  // Deploy BuildingFactory
  const buildingFactoryFactory = await ethers.getContractFactory('BuildingFactory', owner);
  const buildingFactoryBeacon = await upgrades.deployBeacon(buildingFactoryFactory);
  console.log("BuildingFactoryBeacon deployed at:", buildingFactoryBeacon.target);

  // TREX SUITE ------------------------------------
  const claimTopicsRegistryImplementation = await ethers.deployContract('ClaimTopicsRegistry', owner);
  console.log("ClaimTopicsRegistry deployed at:", claimTopicsRegistryImplementation.target);
  const trustedIssuersRegistryImplementation = await ethers.deployContract('TrustedIssuersRegistry', owner);
  console.log("TrustedIssuersRegistry deployed at:", trustedIssuersRegistryImplementation.target);
  const identityRegistryStorageImplementation = await ethers.deployContract('IdentityRegistryStorage', owner);
  console.log("IdentityRegistryStorage deployed at:", identityRegistryStorageImplementation.target);
  const identityRegistryImplementation = await ethers.deployContract('IdentityRegistry', owner);
  console.log("IdentityRegistry deployed at:", identityRegistryImplementation.target);
  const modularComplianceImplementation = await ethers.deployContract('ModularCompliance', owner);
  console.log("ModularCompliance deployed at:", modularComplianceImplementation.target);
  const tokenImplementation = await ethers.deployContract('Token', owner);
  console.log("Token deployed at:", tokenImplementation.target);
  const trexImplementationAuthority = await ethers.deployContract('TREXImplementationAuthority',[true, ethers.ZeroAddress, ethers.ZeroAddress], owner);
  console.log("TREXImplementationAuthority deployed at:", trexImplementationAuthority.target); 
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
  console.log("TREXGateway deployed at:", trexGatewayAddress);
  console.log("TREXFactory deployed at:", trexFactoryAddress);
  await identityFactory.transferOwnership(identityGatewayAddress);

  const buildingFactory = await upgrades.deployBeaconProxy(
    await buildingFactoryBeacon.getAddress(),
    buildingFactoryFactory,
    [
      nftCollectionAddress, 
      uniswapRouterAddress, 
      uniswapFactoryAddress,
      buildingBeaconAddress,
      identityGatewayAddress,
      trexGatewayAddress,
    ],
    { 
      initializer: 'initialize'
    }
  );

  await buildingFactory.waitForDeployment();
  const buildingFactoryAddress = await buildingFactory.getAddress()
  console.log("BuildingFactory deployed at:", buildingFactoryAddress);

  await nftCollection.transferOwnership(buildingFactoryAddress);
  await trexGateway.addDeployer(buildingFactoryAddress);
}

deployFactoryBuilding()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  });
