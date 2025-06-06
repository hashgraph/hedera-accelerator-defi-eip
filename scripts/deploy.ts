import { ethers, upgrades } from 'hardhat';
import { writeFile } from 'fs/promises';
import TestnetDeployments from '../data/deployments/chain-296.json';

import {
  usdcAddress,
  uniswapRouterAddress
} from "../constants";

// Initial function for logs and configs
async function init(): Promise<Record<string, any>> {
  console.log(" - Deploying contracts...");
  return {
    ...TestnetDeployments
  };
}

// Deploy main contracts for the ERC3643 Standart (T-REX)
async function deployERC3643(contracts: Record<string, any>): Promise<Record<string, any>> {
  console.log(' - Deploying ERC3643 contracts...');
  const [deployer] = await ethers.getSigners();

  //Deploy implementations
  const claimTopicsRegistryImplementation = await ethers.deployContract('ClaimTopicsRegistry', deployer);
  const trustedIssuersRegistryImplementation = await ethers.deployContract('TrustedIssuersRegistry', deployer);
  const identityRegistryStorageImplementation = await ethers.deployContract('IdentityRegistryStorage', deployer);
  const identityRegistryImplementation = await ethers.deployContract('IdentityRegistry', deployer);
  const modularComplianceImplementation = await ethers.deployContract('ModularCompliance', deployer);
  const tokenImplementation = await ethers.deployContract('Token', deployer);
  const identityImplementation = await ethers.deployContract('Identity', [deployer.address, true], deployer);
  const identityImplementationAuthority = await ethers.deployContract('ImplementationAuthority', [await identityImplementation.getAddress()], deployer);
  const identityFactory = await ethers.deployContract('IdFactory', [await identityImplementationAuthority.getAddress()], deployer);
  const identityGateway = await ethers.deployContract('IdentityGateway', [await identityFactory.getAddress(), []], deployer);
  const trexImplementationAuthority = await ethers.deployContract('TREXImplementationAuthority', [true, ethers.ZeroAddress, ethers.ZeroAddress], deployer);

  // creates TREX Factory
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

  const trexImplementationAuthorityContract = await ethers.getContractAt(
    "TREXImplementationAuthority",
    await trexImplementationAuthority.getAddress()
  );

  await trexImplementationAuthorityContract.addAndUseTREXVersion(versionStruct, contractsStruct, { gasLimit: 15000000 });


  const TREXFactory = await ethers.getContractFactory('TREXFactory');
  const trexFactory = await TREXFactory.deploy(
    await trexImplementationAuthority.getAddress(),
    await identityFactory.getAddress(),
    { gasLimit: 15000000 }
  );
  await trexFactory.waitForDeployment();

  await identityFactory.addTokenFactory(await trexFactory.getAddress());

  const TREXGateway = await ethers.getContractFactory('TREXGateway');
  const trexGateway = await TREXGateway.deploy(
    await trexFactory.getAddress(),
    true,
    { gasLimit: 15000000 }
  );
  await trexGateway.waitForDeployment();

  await trexFactory.connect(deployer).transferOwnership(await trexGateway.getAddress());
  await identityFactory.connect(deployer).transferOwnership(await identityGateway.getAddress());

  return {
    ...contracts,
    implementations: {
      Token: await tokenImplementation.getAddress(),
      ClaimTopicsRegistry: await claimTopicsRegistryImplementation.getAddress(),
      TrustedIssuersRegistry: await trustedIssuersRegistryImplementation.getAddress(),
      IdentityRegistryStorage: await identityRegistryStorageImplementation.getAddress(),
      IdentityRegistry: await identityRegistryImplementation.getAddress(),
      ModularCompliance: await modularComplianceImplementation.getAddress(),
      Identity: await identityImplementation.getAddress(),
      ImplementationAuthority: await identityImplementationAuthority.getAddress(),
    },
    factories: {
      IdFactory: await identityFactory.getAddress(),
      TREXImplementationAuthority: await trexImplementationAuthority.getAddress(),
      TREXFactory: await trexFactory.getAddress(),
      TREXGateway: await trexGateway.getAddress(),
      IdentityGateway: await identityGateway.getAddress(),
    }
  }

}

async function deployComplianceModules(contracts: Record<string, any>): Promise<Record<string, any>> {
  const [deployer] = await ethers.getSigners();

  // Deploy compliance Modules
  const requiresNFTModule = await ethers.deployContract('RequiresNFTModule', deployer);
  const countryAllowModule = await ethers.deployContract('CountryAllowModule', deployer);
  const maxOwnershipByCountryModule = await ethers.deployContract('MaxOwnershipByCountryModule', deployer);
  const maxTenPercentOwnershipModule = await ethers.deployContract('MaxTenPercentOwnershipModule', deployer);
  const onlyUsaModule = await ethers.deployContract('OnlyUsaModule', deployer);
  const transferLimitOneHundredModule = await ethers.deployContract('TransferLimitOneHundredModule', deployer);

  return {
    ...contracts,
    compliance: {
      RequiresNFTModule: await requiresNFTModule.getAddress(),
      CountryAllowModule: await countryAllowModule.getAddress(),
      MaxOwnershipByCountryModule: await maxOwnershipByCountryModule.getAddress(),
      MaxTenPercentOwnershipModule: await maxTenPercentOwnershipModule.getAddress(),
      OnlyUsaModule: await onlyUsaModule.getAddress(),
      TransferLimitOneHundredModule: await transferLimitOneHundredModule.getAddress(),
    }
  }
}

async function deployVaultFactory(contracts: Record<string, any>): Promise<Record<string, any>> {
  console.log(' - Deploying Vault Factory...');
  const [deployer] = await ethers.getSigners();

  const VaultFactory = await ethers.getContractFactory("VaultFactory");
  const vaultFactory = await VaultFactory.deploy({ from: deployer.address });
  await vaultFactory.waitForDeployment();

  return {
    ...contracts,
    vault: {
      ...contracts.vault,
      VaultFactory: vaultFactory.target,
    }
  };
}

// Deploy Async Vault Factory
async function deployAsyncVaultFactory(contracts: Record<string, any>): Promise<Record<string, any>> {
  console.log(' - Deploying Async Vault Factory...');
  const [deployer] = await ethers.getSigners();

  const AsyncVaultFactory = await ethers.getContractFactory("AsyncVaultFactory");
  const asyncVaultFactory = await AsyncVaultFactory.deploy(
    { from: deployer.address, gasLimit: 15000000 }
  );
  await asyncVaultFactory.waitForDeployment();

  return {
    ...contracts,
    asyncVault: {
      AsyncVaultFactory: asyncVaultFactory.target
    }
  };
}

// Deploy Slice
async function deploySliceFactory(contracts: Record<string, any>): Promise<Record<string, any>> {
  console.log(' - Deploying Slice Factory...');

  const SliceFactory = await ethers.getContractFactory("SliceFactory");
  const sliceFactory = await SliceFactory.deploy();
  await sliceFactory.waitForDeployment();

  return {
    ...contracts,
    slice: {
      ...contracts.slice,
      SliceFactory: sliceFactory.target
    }
  };
}

// Deploy AutoCompounder Factory
async function deployAutoCompounderFactory(contracts: Record<string, any>): Promise<Record<string, any>> {
  console.log(' - Deploying AutoCompounder Factory...');

  const AutoCompounderFactory = await ethers.getContractFactory("AutoCompounderFactory");
  const autoCompounderFactory = await AutoCompounderFactory.deploy();
  await autoCompounderFactory.waitForDeployment();

  return {
    ...contracts,
    autoCompounder: {
      AutoCompounderFactory: autoCompounderFactory.target
    }
  };
}

// deploy NFT metadata collection
async function deployERC721Metadata(contracts: Record<string, any>): Promise<Record<string, any>> {
  const nftCollectionFactory = await ethers.getContractFactory('ERC721Metadata');
  const ERC721Metadata = await nftCollectionFactory.deploy("Buildings R Us", "BRUS",);
  await ERC721Metadata.waitForDeployment();
  const ERC721MetadataAddress = await ERC721Metadata.getAddress();

  return {
    ...contracts,
    implementations: {
      ...contracts.implementations,
      ERC721Metadata: ERC721MetadataAddress,
    }
  }
}

// deploy upgradeable BuildingFactory
async function deployBuildingFactory(contracts: Record<string, any>): Promise<Record<string, any>> {
  const buildingFact = await ethers.getContractFactory('Building');
  const buildingBeacon = await upgrades.deployBeacon(buildingFact);
  await buildingBeacon.waitForDeployment();
  const buildingBeaconAddress = await buildingBeacon.getAddress();

  const buildingFactoryFactory = await ethers.getContractFactory('BuildingFactory', { libraries: contracts.libraries });
  const buildingFactoryBeacon = await upgrades.deployBeacon(buildingFactoryFactory, { unsafeAllow: ["external-library-linking"] } );
  await buildingFactoryBeacon.waitForDeployment();
  const buildingFactoryBeaconAddress = await buildingFactoryBeacon.getAddress();
  const identityGateway = await ethers.getContractAt('IdentityGateway', contracts.factories.IdentityGateway);
  const identityGatewayAddress = await identityGateway.getAddress();

  const uniswapRouter = await ethers.getContractAt('UniswapRouterMock', uniswapRouterAddress);
  const uniswapFactoryAddress = await uniswapRouter.factory();

  const trexGatewayAddress = contracts.factories.TREXGateway;
  const trexGateway = await ethers.getContractAt('TREXGateway', trexGatewayAddress);

  // Beacon Upgradable Pattern for Treasury
  const treasuryImplementation = await ethers.deployContract('Treasury', { gasLimit: 15000000 });
  await treasuryImplementation.waitForDeployment();
  const treasuryImplementationAddress = await treasuryImplementation.getAddress();
  const treasuryBeaconFactory = await ethers.getContractFactory('TreasuryBeacon');
  const treasuryBeacon = await treasuryBeaconFactory.deploy(treasuryImplementationAddress, { gasLimit: 15000000 })
  await treasuryBeacon.waitForDeployment();
  const treasuryBeaconAddress = await treasuryBeacon.getAddress();

  // Beacon Upgradable Pattern for Treasury
  const governanceImplementation = await ethers.deployContract('BuildingGovernance');
  await governanceImplementation.waitForDeployment();
  const governanceImplementationAddress = await governanceImplementation.getAddress();
  const governanceBeaconFactory = await ethers.getContractFactory('BuildingGovernanceBeacon');
  const governanceBeacon = await governanceBeaconFactory.deploy(governanceImplementationAddress, { gasLimit: 15000000 })
  await governanceBeacon.waitForDeployment();
  const governanceBeaconAddress = await governanceBeacon.getAddress();

  const buildingFactory = await upgrades.deployBeaconProxy(
    buildingFactoryBeaconAddress,
    buildingFactoryFactory,
    [
      contracts.implementations.ERC721Metadata,
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
      initializer: 'initialize'
    }
  );

  await buildingFactory.waitForDeployment();
  const buildingFactoryAddress = await buildingFactory.getAddress()

  const nftCollection = await ethers.getContractAt('ERC721Metadata', contracts.implementations.ERC721Metadata);
  await nftCollection.transferOwnership(buildingFactoryAddress);
  await trexGateway.addDeployer(buildingFactoryAddress);

  return {
    ...contracts,
    factories: {
      ...contracts.factories,
      BuildingFactory: buildingFactoryAddress
    }
  }
}

async function deployAudit(contracts: Record<string, any>): Promise<Record<string, any>> {
  const AuditRegistry = await ethers.getContractFactory('AuditRegistry');
  const auditRegistry = await AuditRegistry.deploy();
  await auditRegistry.waitForDeployment();
  const auditRegistryAddress = await auditRegistry.getAddress();

  return {
    ...contracts,
    implementations: {
      ...contracts.implementations,
      AuditRegistry: auditRegistryAddress,
    }
  }
}

async function deployExchange(contracts: Record<string, any>): Promise<Record<string, any>> {
  const oneSidedExchangeImplementation = await ethers.deployContract('OneSidedExchange');
  const exchangeAddress = await oneSidedExchangeImplementation.getAddress();

  return {
    ...contracts,
    implementations: {
      ...contracts.implementations,
      OneSidedExchange: exchangeAddress
    }
  }
}

async function deployLibraries(contracts: Record<string, any>): Promise<Record<string, any>> { 
  const libraries = {
    "BuildingTokenLib" : await (await (await ethers.deployContract("BuildingTokenLib")).waitForDeployment()).getAddress(),
    "BuildingGovernanceLib" : await (await (await ethers.deployContract("BuildingGovernanceLib")).waitForDeployment()).getAddress(),
    "BuildingTreasuryLib" : await (await (await ethers.deployContract("BuildingTreasuryLib")).waitForDeployment()).getAddress(),
    "BuildingVaultLib" : await (await (await ethers.deployContract("BuildingVaultLib")).waitForDeployment()).getAddress(),
    "BuildingAutoCompounderLib" : await (await (await ethers.deployContract("BuildingAutoCompounderLib")).waitForDeployment()).getAddress(),
  }

  return {
    ...contracts,
    libraries
  }
}

async function logContracts(contracts: Record<string, any>): Promise<Record<string, any>> {
  console.log(contracts);
  return contracts;
}

// creates a deployment file into data/deployments (eg: data/deployments/mainnet.json)
async function exportDeploymentVersion(contracts: Record<string, any>): Promise<Record<string, any>> {
  console.log(' - Export Deployment contract addresses...');
  const network = await ethers.provider.getNetwork();
  const filePath = `./data/deployments/chain-${network.chainId.toString()}.json`
  const jsonData = JSON.stringify(contracts, null, 2);
  await writeFile(filePath, jsonData, 'utf-8');
  console.log(` - Deployment addresses written to ${filePath}`);

  return contracts;
}

// Finish function
async function finish(): Promise<void> {
  console.log(' - Finished');
  process.exit();
}

init()
  // add subsequent deployment script after this comment
  .then(deployERC3643)
  .then(deployComplianceModules)
  .then(deployVaultFactory)
  .then(deployAsyncVaultFactory)
  .then(deploySliceFactory)
  .then(deployAutoCompounderFactory)
  .then(deployERC721Metadata)
  .then(deployLibraries)
  .then(deployBuildingFactory)
  .then(deployAudit)
  .then(deployExchange)
  .then(exportDeploymentVersion)
  .then(logContracts)
  .then(finish)
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });


