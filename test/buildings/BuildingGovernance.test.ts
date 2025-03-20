import { expect, ethers, upgrades } from '../setup';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

async function deployFixture() {
  const [owner, notOwner] = await ethers.getSigners();

  const buildingGovernanceFactory = await ethers.getContractFactory('BuildingGovernance');
  const buildingGovernanceBeacon = await upgrades.deployBeacon(
    buildingGovernanceFactory, 
  );

  const governanceToken = await ethers.deployContract('BuildingERC20', ['test', 'test', 18]);
  const governanceTokenAddress = await governanceToken.getAddress();
  const governanceName = "Governance";
  const initialOwner = owner.address;
  const treasuryAddress = ethers.ZeroAddress; // TODO: set treasury
  
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


  return {
    owner,
    notOwner,
    buildingGovernance,
    buildingGovernanceBeacon,
    buildingGovernanceFactory
  }
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
        buildingGovernance,
      } = await loadFixture(deployFixture);

       const level = 0; // Governor Vote
       const description = "Host a Community Workshop";
       await buildingGovernance.createTextProposal(level, description);
    });
  });

  describe('.createPaymentProposal()', () => {
    it('should create payment proposal', async () => {
      const { 
        buildingGovernance,
      } = await loadFixture(deployFixture);

      const token = ethers.ZeroAddress;
      const amount = ethers.parseEther('1');
      const to = ethers.ZeroAddress;
      const description = "Replace Lobby Furniture";
      await buildingGovernance.createPaymentProposal(token, amount, to, description);
    });
  });
});
