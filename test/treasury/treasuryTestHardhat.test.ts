import { expect, ethers } from '../setup';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

async function deployFixture() {
  const [owner, governance, business, addr1, addr2] = await ethers.getSigners();

  // mock USDC token
  const ERC20Mock = await ethers.getContractFactory('ERC20Mock', owner);
  const usdc = await ERC20Mock.deploy(
    'USD Coin',
    'USDC',
    await owner.getAddress(),
    ethers.parseUnits('1000000', 6)
  );
  await usdc.waitForDeployment();

  // mock vault
  const VaultMock = await ethers.getContractFactory('VaultMock', owner);
  const vault = await VaultMock.deploy(usdc.target);
  await vault.waitForDeployment();

  // mock building token
  const BuildingTokenMock = await ethers.getContractFactory('ERC20Mock', owner);
  const buildingToken = await BuildingTokenMock.deploy(
    'Building Token',
    'BT',
    await owner.getAddress(),
    ethers.parseUnits('1000000', 18)
  );
  await buildingToken.waitForDeployment();

  // treasury 
  const Treasury = await ethers.getContractFactory('Treasury', owner);
  const N_PERCENTAGE = 2000; // 20% to business
  const RESERVE_AMOUNT = ethers.parseUnits('10000', 6);

  const treasury = await Treasury.deploy(
    usdc.target,
    buildingToken.target, // building token address
    vault.target,
    RESERVE_AMOUNT,
    N_PERCENTAGE,
    await business.getAddress(),
    await governance.getAddress()
  );
  await treasury.waitForDeployment();

  // USDC to addr1 and addr2 for testing
  await usdc.connect(owner).transfer(await addr1.getAddress(), ethers.parseUnits('50000', 6));
  await usdc.connect(owner).transfer(await addr2.getAddress(), ethers.parseUnits('50000', 6));

  return {
    owner,
    governance,
    business,
    addr1,
    addr2,
    usdc,
    vault,
    treasury,
    buildingToken, 
  };
}


describe('Treasury Contract', () => {
  describe('Deployment', () => {
    it('should deploy contracts successfully', async () => {
      const { usdc, vault, treasury } = await loadFixture(deployFixture);

      expect(usdc.target).to.be.a('string');
      expect(vault.target).to.be.a('string');
      expect(treasury.target).to.be.a('string');
    });
  });

  describe('Fund Distribution', () => {
    it('should distribute funds correctly on deposit', async () => {
      const { usdc, treasury, vault, business, addr1 } = await loadFixture(deployFixture);

      // addr1 approves treasury to spend USDC
      await usdc.connect(addr1).approve(treasury.target, ethers.parseUnits('50000', 6));

      // addr1 deposits 50,000 USDC into treasury
      await treasury.connect(addr1).deposit(ethers.parseUnits('50000', 6));

      // balance check
      const businessBalance = await usdc.balanceOf(await business.getAddress());
      const expectedBusinessAmount = ethers.parseUnits('10000', 6); // 20% of 50000

      expect(businessBalance).to.equal(expectedBusinessAmount);

      const treasuryBalance = await usdc.balanceOf(treasury.target);
      const expectedTreasuryAmount = ethers.parseUnits('10000', 6); // reserve

      expect(treasuryBalance).to.equal(expectedTreasuryAmount);

      const vaultBalance = await usdc.balanceOf(vault.target);
      const expectedVaultAmount = ethers.parseUnits('30000', 6); // leftover

      expect(vaultBalance).to.equal(expectedVaultAmount);
    });
  });

  describe('Governance-Controlled Payments', () => {
    it('should allow governance to make payments', async () => {
      const { usdc, treasury, vault, governance, addr2, owner } = await loadFixture(deployFixture);

      // send USDC to Treasury
      await usdc.connect(owner).transfer(treasury.target, ethers.parseUnits('20000', 6));

      // governance makes a payment
      await treasury.connect(governance).makePayment(await addr2.getAddress(), ethers.parseUnits('5000', 6));

      const addr2Balance = await usdc.balanceOf(await addr2.getAddress());
      expect(addr2Balance).to.equal(ethers.parseUnits('55000', 6)); // 50000 initial + 5000 payment

      const treasuryBalance = await usdc.balanceOf(treasury.target);
      expect(treasuryBalance).to.equal(ethers.parseUnits('10000', 6)); // reserve

      const vaultBalance = await usdc.balanceOf(vault.target);
      expect(vaultBalance).to.equal(ethers.parseUnits('5000', 6)); // excess forwarded to vault
    });

    it('should not allow non-governance to make payments', async () => {
      const { usdc, treasury, addr1, addr2, owner } = await loadFixture(deployFixture);
    
      // owner approves and deposits USDC
      await usdc.connect(owner).approve(treasury.target, ethers.parseUnits('20000', 6));
      await treasury.connect(owner).deposit(ethers.parseUnits('20000', 6));
    
      const GOVERNANCE_ROLE = await treasury.GOVERNANCE_ROLE();
    
      // addr1 tries to make a payment
      await expect(
        treasury.connect(addr1).makePayment(await addr2.getAddress(), ethers.parseUnits('5000', 6))
      ).to.be.revertedWithCustomError(treasury, 'AccessControlUnauthorizedAccount')
       .withArgs(await addr1.getAddress(), GOVERNANCE_ROLE);
    }); 
  });   

  describe('Forwarding Excess Funds', () => {
    it('should forward excess funds to Vault when reserve is exceeded', async () => {
      const { usdc, treasury, vault, owner, business } = await loadFixture(deployFixture);

      // owner approves treasury to spend USDC
      await usdc.connect(owner).approve(treasury.target, ethers.parseUnits('50000', 6));

      // owner deposits 50000 USDC into treasury
      await treasury.connect(owner).deposit(ethers.parseUnits('50000', 6));

      // balance check
      const expectedBusinessBalance = ethers.parseUnits('10000', 6); // 20% of 50000
      const expectedTreasuryBalance = ethers.parseUnits('10000', 6); // reserve amount
      const expectedVaultBalance = ethers.parseUnits('30000', 6); // remaining amount

      const businessBalance = await usdc.balanceOf(await business.getAddress());
      const treasuryBalance = await usdc.balanceOf(treasury.target);
      const vaultBalance = await usdc.balanceOf(vault.target);

      expect(businessBalance).to.equal(expectedBusinessBalance);
      expect(treasuryBalance).to.equal(expectedTreasuryBalance);
      expect(vaultBalance).to.equal(expectedVaultBalance);
    });
  });

  describe('Updating Reserve Amount', () => {
    it('should not allow non-governance to update reserve amount', async () => {
      const { treasury, addr1 } = await loadFixture(deployFixture);
    
      const GOVERNANCE_ROLE = await treasury.GOVERNANCE_ROLE();
    
      await expect(
        treasury.connect(addr1).setReserveAmount(ethers.parseUnits('20000', 6))
      ).to.be.revertedWithCustomError(treasury, 'AccessControlUnauthorizedAccount')
       .withArgs(await addr1.getAddress(), GOVERNANCE_ROLE);
    });    
  });
});