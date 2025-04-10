import { LogDescription } from 'ethers';
import { BuildingGovernance } from '../../typechain-types';
import { expect, ethers, upgrades } from '../setup';
import { loadFixture, mine } from '@nomicfoundation/hardhat-network-helpers';

async function deployFixture() {
  const [owner, notOwner, voter1, voter2, voter3] = await ethers.getSigners();

  const buildingGovernanceFactory = await ethers.getContractFactory('BuildingGovernance');
  const buildingGovernanceBeacon = await upgrades.deployBeacon(
    buildingGovernanceFactory, 
  );

  const governanceToken = await ethers.deployContract('BuildingERC20', ['test', 'test', 18]);
  const governanceTokenAddress = await governanceToken.getAddress();
  const governanceName = "Governance";
  const initialOwner = owner.address;

  // mint and delegate tokens
  const mintAmount = ethers.parseEther('1000');
  await governanceToken.mint(owner.address, mintAmount);
  await governanceToken.mint(voter1.address, mintAmount);
  await governanceToken.mint(voter2.address, mintAmount);
  await governanceToken.mint(voter3.address, mintAmount);
  await governanceToken.connect(voter1).delegate(voter1.address);
  await governanceToken.connect(voter2).delegate(voter2.address);
  await governanceToken.connect(voter3).delegate(voter3.address);

  const ERC20Mock = await ethers.getContractFactory('ERC20Mock', owner);
  const usdc = await ERC20Mock.deploy(
    'USD Coin',
    'USDC',
    6n,
  );
  await usdc.waitForDeployment();
  const usdcAddress = await usdc.getAddress();

  // create Treasury
  const N_PERCENTAGE = 2000; // 20% to business
  const RESERVE_AMOUNT = ethers.parseUnits('1000', 6);

  const treasuryImplmentation = await ethers.getContractFactory('Treasury');

  // Deploy the Beacon which will hold the implementation address
  const beacon = await upgrades.deployBeacon(treasuryImplmentation);
  await beacon.waitForDeployment();

  const treasuryProxy = await upgrades.deployBeaconProxy(
      beacon,
      treasuryImplmentation,
      [
        usdcAddress,
        RESERVE_AMOUNT,
        N_PERCENTAGE,
        owner.address,
        owner.address,
        owner.address // buildingFactory
      ],
      { 
        initializer: 'initialize'
      }
  );

  await treasuryProxy.waitForDeployment();

  const treasuryAddress = await treasuryProxy.getAddress();
  const treasury = await ethers.getContractAt('Treasury', treasuryAddress);
  await treasury.grantFactoryRole(owner.address);

  const VaultFactory = await ethers.getContractFactory("VaultFactory");
  const vaultFactory = await VaultFactory.deploy({ from: owner.address });
  await vaultFactory.waitForDeployment();

  // create Vault
  const vaultDetails = {
    stakingToken: governanceTokenAddress,
    shareTokenName: await governanceToken.name(),
    shareTokenSymbol: await governanceToken.symbol(),
    vaultRewardController: treasuryAddress,
    feeConfigController: initialOwner,
    cliff : 0,
    unlockDuration : 0
  }

  const feeConfig = {
    receiver: ethers.ZeroAddress,
    token: ethers.ZeroAddress,
    feePercentage: 0
  }

  const salt = await vaultFactory.generateSalt(initialOwner, governanceTokenAddress, 0);

  const tx = await vaultFactory.deployVault(
    salt,
    vaultDetails,
    feeConfig,
    { from: owner.address, gasLimit: 3000000, value: ethers.parseEther("23") }
  );

  await tx.wait();

  const vaultAddress = await vaultFactory.vaultDeployed(salt);
  const vault = await ethers.getContractAt('BasicVault', vaultAddress);

  await treasury.addVault(vaultAddress);

  // stake tokens to vault
  await governanceToken.approve(vaultAddress, mintAmount);
  await vault.deposit(mintAmount, owner.address);

  // fund treasury
  const fundingAmount = ethers.parseUnits('10000', 6);
  await usdc.mint(owner.address, fundingAmount);
  await usdc.approve(treasuryAddress, fundingAmount);
  await treasury.deposit(fundingAmount);

  
  const buildingGovernance = await upgrades.deployBeaconProxy(
    await buildingGovernanceBeacon.getAddress(), 
    buildingGovernanceFactory,
    [
      governanceTokenAddress, 
      governanceName, 
      initialOwner, 
      treasuryAddress
    ], 
    { 
      initializer: 'initialize'
    }
  );

  await treasury.grantGovernanceRole(await buildingGovernance.getAddress());

  const governance = await ethers.getContractAt('BuildingGovernance', await buildingGovernance.getAddress());

  return {
    owner,
    notOwner,
    voter1, 
    voter2, 
    voter3,
    governanceToken,
    buildingGovernance,
    buildingGovernanceBeacon,
    buildingGovernanceFactory,
    governance,
    treasury,
    vault,
    usdc
  }
}

async function getProposalId(governance: BuildingGovernance, blockNumber: number) {
  // Decode the event using queryFilter
  const logs = await governance.queryFilter(governance.filters.ProposalCreated, blockNumber, blockNumber);

  // Decode the log using the contract's interface  
  const decodedEvent = governance.interface.parseLog(logs[0]) as LogDescription; // Get the first log

  // Extract and verify the emitted address  
  return decodedEvent.args[0]; 
}

describe('BuildingGovernance', () => {

  describe('upgrade', () => {
    it('should be uprgradable', async () => {
      const { 
        buildingGovernance,
        buildingGovernanceBeacon
       } = await loadFixture(deployFixture);

      const previousBuildingAddress = await buildingGovernance.getAddress();
      const v2contractFactory = await ethers.getContractFactory('BuildingGovernanceMock');
      await upgrades.upgradeBeacon(await buildingGovernanceBeacon.getAddress(), v2contractFactory);

      const upgradedBuildingGovernance = await ethers.getContractAt('BuildingGovernanceMock', previousBuildingAddress);

      expect(await upgradedBuildingGovernance.getAddress()).to.be.hexEqual(previousBuildingAddress);
      expect(await upgradedBuildingGovernance.version()).to.be.equal('2.0');
    });
  });

  describe('.createTextProposal()', () => {
    it('should create text proposal', async () => {
      const { 
        owner,
        governance,
      } = await loadFixture(deployFixture);

       const level = 0; // Governor Vote
       const description = "Host a Community Workshop";
       const tx = await governance.createTextProposal(level, description);
       const proposalId = getProposalId(governance, tx.blockNumber as number);

      const proposalType = 0 // text
      const proposer = owner.address
      const receiver = ethers.ZeroAddress // text proposal have zero address for receiver
      const amount = 0n // text proposal have zero amount

      await expect(tx).to.emit(governance, 'ProposalDefined').withArgs(proposalId, proposalType, proposer, receiver, amount);
    });
  });

  describe('.createPaymentProposal()', () => {
    it('should create payment proposal', async () => {
      const { 
        governance,
        owner
      } = await loadFixture(deployFixture);

      const amount = ethers.parseEther('1');
      const to = ethers.ZeroAddress;
      const description = "Replace Lobby Furniture";
      const tx = await governance.createPaymentProposal(amount, to, description);
      const proposalId = getProposalId(governance, tx.blockNumber as number);

      const proposalType = 1 // payment
      const proposer = owner.address
      const receiver = to;

      await expect(tx).to.emit(governance, 'ProposalDefined').withArgs(proposalId, proposalType, proposer, receiver, amount);
    });

    it('should execute payment proposal', async () => {
      const { 
        governance,
        treasury,
        usdc,
        voter1, voter2, voter3
      } = await loadFixture(deployFixture);

      const amount = ethers.parseUnits('1', 6); // 1 USDT
      const to = ethers.Wallet.createRandom();
      const description = "Proposal #1: Pay a dollar";

      // user should have 0 usdc balance
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
      const targetAbi = [
        "function makePayment(address to, uint256 amount) external"
      ];

      const calldata = new ethers.Interface(targetAbi).encodeFunctionData("makePayment", [to.address, amount]);

      await governance.execute(
        [treasury.target],
        [0n],
        [calldata],
        ethers.id(description)
      );

      // address should have 1 usdc balance after payment executed; 
      expect(await usdc.balanceOf(to.address)).to.be.eq(ethers.parseUnits('1', 6));

    });
  });

  describe('.executeTextProposal()', () => {
    it('should execute text proposal', async () => {
      const { 
        governance,
        voter1, voter2, voter3
      } = await loadFixture(deployFixture);

      const description = "Proposal #1: Any Text Proposal";

      const tx1 = await governance.createTextProposal(0, description);
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
      await governance.executeTextProposal(proposalId);

    });
  });

  describe('.executePaymentProposal()', () => {
    it('should execute payment proposal', async () => {
      const { 
        governance,
        usdc,
        voter1, voter2, voter3
      } = await loadFixture(deployFixture);

      const amount = ethers.parseUnits('1', 6); // 1 USDT
      const to = ethers.Wallet.createRandom();
      const description = "Proposal #1: Pay a dollar";

      // user should have 0 usdc balance
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

      // address should have 1 usdc balance after payment executed; 
      expect(await usdc.balanceOf(to.address)).to.be.eq(ethers.parseUnits('1', 6));

    });
  });

  describe('.executeChangeReserveProposal()', () => {
    it('should execute change reserve proposal', async () => {
      const { 
        governance,
        treasury,
        voter1, voter2, voter3
      } = await loadFixture(deployFixture);

      const oldReserve = await treasury.reserve();

      const amount = ethers.parseUnits('2000', 6); // 2k USDT
      const description = "Proposal #1: increase reserve";

      const tx1 = await governance.createChangeReserveProposal(amount, description);
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
      await governance.executeChangeReserveProposal(proposalId);

      // address should have 1 usdc balance after payment executed; 
      expect(await treasury.reserve()).not.to.be.eq(oldReserve);
      expect(await treasury.reserve()).to.be.eq(amount);

    });
  });
});
