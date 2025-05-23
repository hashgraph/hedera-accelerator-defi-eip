import { Signer, AbiCoder } from 'ethers';
import { ethers } from 'hardhat';
// import OnchainID from '@onchain-id/solidity';
import * as dotenv from 'dotenv'

dotenv.config();

export async function deployIdentityProxy(implementationAuthority: string, managementKey: string, signer: Signer) {
  // const identity = await new ethers.ContractFactory(OnchainID.contracts.IdentityProxy.abi, OnchainID.contracts.IdentityProxy.bytecode, signer).deploy(
  //   implementationAuthority,
  //   managementKey,
  // );

  const identity = await ethers.deployContract('IdentityProxy', [implementationAuthority, managementKey], signer);

  return ethers.getContractAt('Identity', await identity.getAddress(), signer);
}

export async function deployFullSuiteFixture() {
  const [deployer, tokenIssuer, tokenAgent, tokenAdmin, claimIssuer, aliceWallet, bobWallet, charlieWallet, davidWallet, anotherWallet] =
    await ethers.getSigners();
  const claimIssuerSigningKey = ethers.Wallet.createRandom();
  const aliceActionKey = ethers.Wallet.createRandom();

  // Deploy implementations
  const claimTopicsRegistryImplementation = await ethers.deployContract('ClaimTopicsRegistry', deployer);
  const trustedIssuersRegistryImplementation = await ethers.deployContract('TrustedIssuersRegistry', deployer);
  const identityRegistryStorageImplementation = await ethers.deployContract('IdentityRegistryStorage', deployer);
  const identityRegistryImplementation = await ethers.deployContract('IdentityRegistry', deployer);
  const modularComplianceImplementation = await ethers.deployContract('ModularCompliance', deployer);
  const tokenImplementation = await ethers.deployContract('TokenVotes', deployer);
  // const identityImplementation = await new ethers.ContractFactory(
  //   OnchainID.contracts.Identity.abi,
  //   OnchainID.contracts.Identity.bytecode,
  //   deployer,
  // ).deploy(deployer.address, true);
  const identityImplementation = await ethers.deployContract('Identity', [deployer.address, true], deployer);

  // const identityImplementationAuthority = await new ethers.ContractFactory(
  //   OnchainID.contracts.ImplementationAuthority.abi,
  //   OnchainID.contracts.ImplementationAuthority.bytecode,
  //   deployer,
  // ).deploy(await identityImplementation.getAddress());

  const identityImplementationAuthority = await ethers.deployContract('ImplementationAuthority', [await identityImplementation.getAddress()], deployer);

  // const identityFactory = await new ethers.ContractFactory(OnchainID.contracts.Factory.abi, OnchainID.contracts.Factory.bytecode, deployer).deploy(
  //   await identityImplementationAuthority.getAddress(),
  // ) as IIdFactory;

  const identityFactory = await ethers.deployContract('IdFactory', [await identityImplementationAuthority.getAddress()], deployer);

  const trexImplementationAuthority = await ethers.deployContract(
    'TREXImplementationAuthority',
    [true, ethers.ZeroAddress, ethers.ZeroAddress],
    deployer,
  );
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
  await trexImplementationAuthority.connect(deployer).addAndUseTREXVersion(versionStruct, contractsStruct);

  const trexFactory = await ethers.deployContract('TREXFactory', [await trexImplementationAuthority.getAddress(), await identityFactory.getAddress()], deployer);
  await identityFactory.connect(deployer).addTokenFactory(await trexFactory.getAddress());

  const claimTopicsRegistry = await ethers
    .deployContract('ClaimTopicsRegistryProxy', [await trexImplementationAuthority.getAddress()], deployer)
    .then(async (proxy) => ethers.getContractAt('ClaimTopicsRegistry', await proxy.getAddress()));

  const trustedIssuersRegistry = await ethers
    .deployContract('TrustedIssuersRegistryProxy', [await trexImplementationAuthority.getAddress()], deployer)
    .then(async (proxy) => ethers.getContractAt('TrustedIssuersRegistry', await proxy.getAddress()));

  const identityRegistryStorage = await ethers
    .deployContract('IdentityRegistryStorageProxy', [await trexImplementationAuthority.getAddress()], deployer)
    .then(async (proxy) => ethers.getContractAt('IdentityRegistryStorage', await proxy.getAddress()));

  const defaultCompliance = await ethers.deployContract('DefaultCompliance', deployer);

  const identityRegistry = await ethers
    .deployContract(
      'IdentityRegistryProxy',
      [await trexImplementationAuthority.getAddress(), await trustedIssuersRegistry.getAddress(), await claimTopicsRegistry.getAddress(), await identityRegistryStorage.getAddress()],
      deployer,
    )
    .then(async (proxy) => ethers.getContractAt('IdentityRegistry', await proxy.getAddress()));

  const tokenOID = await deployIdentityProxy(await identityImplementationAuthority.getAddress(), await tokenIssuer.getAddress(), deployer);
  const tokenName = 'TREXDINO';
  const tokenSymbol = 'TREX';
  const tokenDecimals = 0n;
  const token = await ethers
    .deployContract(
      'TokenProxy',
      [
        await trexImplementationAuthority.getAddress(),
        await identityRegistry.getAddress(),
        await defaultCompliance.getAddress(),
        tokenName,
        tokenSymbol,
        tokenDecimals,
        await tokenOID.getAddress(),
      ],
      deployer,
    )
    .then(async (proxy) => ethers.getContractAt('Token', await proxy.getAddress()));

  const agentManager = await ethers.deployContract('AgentManager', [await token.getAddress()], tokenAgent);

  await identityRegistryStorage.connect(deployer).bindIdentityRegistry(await identityRegistry.getAddress());

  await token.connect(deployer).addAgent(tokenAgent.address);

  const claimTopics = [ethers.id('CLAIM_TOPIC')];
  await claimTopicsRegistry.connect(deployer).addClaimTopic(claimTopics[0]);

  const claimIssuerContract = await ethers.deployContract('ClaimIssuer', [claimIssuer.address], claimIssuer);
  await claimIssuerContract
    .connect(claimIssuer)
    .addKey(ethers.keccak256(AbiCoder.defaultAbiCoder().encode(['address'], [claimIssuerSigningKey.address])), 3, 1);

  await trustedIssuersRegistry.connect(deployer).addTrustedIssuer(await claimIssuerContract.getAddress(), claimTopics);

  const aliceIdentity = await deployIdentityProxy(await identityImplementationAuthority.getAddress(), aliceWallet.address, deployer);
  await aliceIdentity
    .connect(aliceWallet)
    .addKey(ethers.keccak256(AbiCoder.defaultAbiCoder().encode(['address'], [aliceActionKey.address])), 2, 1);
  const bobIdentity = await deployIdentityProxy(await identityImplementationAuthority.getAddress(), bobWallet.address, deployer);
  const charlieIdentity = await deployIdentityProxy(await identityImplementationAuthority.getAddress(), charlieWallet.address, deployer);

  await identityRegistry.connect(deployer).addAgent(tokenAgent.address);
  await identityRegistry.connect(deployer).addAgent(await token.getAddress());

  await identityRegistry
    .connect(tokenAgent)
    .batchRegisterIdentity([aliceWallet.address, bobWallet.address], [await aliceIdentity.getAddress(), await bobIdentity.getAddress()], [840, 76]); // alice is from US and Bob from Brazil

  const claimForAlice = {
    data: ethers.hexlify(ethers.toUtf8Bytes('Some claim public data.')),
    issuer: await claimIssuerContract.getAddress(),
    topic: claimTopics[0],
    scheme: 1,
    identity: await aliceIdentity.getAddress(),
    signature: '',
  };
  claimForAlice.signature = await claimIssuerSigningKey.signMessage(
    ethers.getBytes(
      ethers.keccak256(
        AbiCoder.defaultAbiCoder().encode(['address', 'uint256', 'bytes'], [claimForAlice.identity, claimForAlice.topic, claimForAlice.data]),
      ),
    ),
  );

  await aliceIdentity
    .connect(aliceWallet)
    .addClaim(claimForAlice.topic, claimForAlice.scheme, claimForAlice.issuer, claimForAlice.signature, claimForAlice.data, '');

  const claimForBob = {
    data: ethers.hexlify(ethers.toUtf8Bytes('Some claim public data.')),
    issuer: await claimIssuerContract.getAddress(),
    topic: claimTopics[0],
    scheme: 1,
    identity: await bobIdentity.getAddress(),
    signature: '',
  };
  claimForBob.signature = await claimIssuerSigningKey.signMessage(
    ethers.getBytes(
      ethers.keccak256(
        AbiCoder.defaultAbiCoder().encode(['address', 'uint256', 'bytes'], [claimForBob.identity, claimForBob.topic, claimForBob.data]),
      ),
    ),
  );

  await bobIdentity
    .connect(bobWallet)
    .addClaim(claimForBob.topic, claimForBob.scheme, claimForBob.issuer, claimForBob.signature, claimForBob.data, '');

  await token.connect(tokenAgent).mint(aliceWallet.address, 1000);
  await token.connect(tokenAgent).mint(bobWallet.address, 500);

  await agentManager.connect(tokenAgent).addAgentAdmin(tokenAdmin.address);
  await token.connect(deployer).addAgent(await agentManager.getAddress());
  await identityRegistry.connect(deployer).addAgent(await agentManager.getAddress());


  return {
    accounts: {
      deployer,
      tokenIssuer,
      tokenAgent,
      tokenAdmin,
      claimIssuer,
      claimIssuerSigningKey,
      aliceActionKey,
      aliceWallet,
      bobWallet,
      charlieWallet,
      davidWallet,
      anotherWallet,
    },
    identities: {
      aliceIdentity,
      bobIdentity,
      charlieIdentity,
    },
    suite: {
      claimIssuerContract,
      claimTopicsRegistry,
      trustedIssuersRegistry,
      identityRegistryStorage,
      defaultCompliance,
      identityRegistry,
      tokenOID,
      token,
      agentManager,
    },
    authorities: {
      trexImplementationAuthority,
      identityImplementationAuthority,
    },
    factories: {
      trexFactory,
      identityFactory,
    },
    implementations: {
      identityImplementation,
      claimTopicsRegistryImplementation,
      trustedIssuersRegistryImplementation,
      identityRegistryStorageImplementation,
      identityRegistryImplementation,
      modularComplianceImplementation,
      tokenImplementation,
    },
  };
}

export async function deploySuiteWithModularCompliancesFixture() {
  const context = await deployFullSuiteFixture();

  const complianceProxy = await ethers.deployContract('ModularComplianceProxy', [await context.authorities.trexImplementationAuthority.getAddress()]);
  const compliance = await ethers.getContractAt('ModularCompliance', await complianceProxy.getAddress());

  const complianceBeta = await ethers.deployContract('ModularCompliance');
  await complianceBeta.init();

  return {
    ...context,
    suite: {
      ...context.suite,
      compliance,
      complianceBeta,
    },
  };
}

export async function deploySuiteWithModuleComplianceBoundToWallet() {
  const context = await deployFullSuiteFixture();

  const compliance = await ethers.deployContract('ModularCompliance');
  await compliance.init();

  const complianceModuleA = await ethers.deployContract('CountryAllowModule');
  await compliance.addModule(await complianceModuleA.getAddress());
  const complianceModuleB = await ethers.deployContract('CountryAllowModule');
  await compliance.addModule(await complianceModuleB.getAddress());

  await compliance.bindToken(context.accounts.charlieWallet.address);

  return {
    ...context,
    suite: {
      ...context.suite,
      compliance,
      complianceModuleA,
      complianceModuleB,
    },
  };
}
