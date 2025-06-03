import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deployComplianceFixture } from '../fixtures/deploy-compliance.fixture';
import { deploySuiteWithModularCompliancesFixture } from '../fixtures/deploy-full-suite.fixture';

async function deployMaxOwnershipFullSuite() {
  const context = await loadFixture(deploySuiteWithModularCompliancesFixture);
  const complianceModule = await ethers.deployContract('MaxOwnershipModule');
  await context.suite.token.connect(context.accounts.tokenAgent).burn(context.accounts.aliceWallet.address, 1000);
  await context.suite.token.connect(context.accounts.tokenAgent).burn(context.accounts.bobWallet.address, 500);
  await context.suite.compliance.bindToken(await context.suite.token.getAddress());
  await context.suite.compliance.addModule(await complianceModule.getAddress());

  return {
    ...context,
    suite: {
      ...context.suite,
      complianceModule,
    },
  };
}

describe('Compliance Module: MaxOwnership', () => {
  it('should deploy the MaxOwnership contract and bind it to the compliance', async () => {
    const context = await loadFixture(deployMaxOwnershipFullSuite);

    expect(await context.suite.complianceModule.getAddress()).not.to.be.undefined;
    expect(await context.suite.compliance.isModuleBound(await context.suite.complianceModule.getAddress())).to.be.true;
  });

  describe('.name', () => {
    it('should return the name of the module', async () => {
      const context = await loadFixture(deployMaxOwnershipFullSuite);

      expect(await context.suite.complianceModule.name()).to.be.equal('MaxOwnershipModule');
    });
  });

  describe('.isPlugAndPlay', () => {
    it('should return false', async () => {
      const context = await loadFixture(deployMaxOwnershipFullSuite);
      expect(await context.suite.complianceModule.isPlugAndPlay()).to.be.false;
    });
  });

  describe('.canComplianceBind', () => {
    describe('when token totalSupply is greater than zero', () => {
      describe('when compliance preset status is false', () => {
        it('should return false', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          await context.suite.token.connect(context.accounts.tokenAgent).mint(context.accounts.aliceWallet.address, 1000);
          expect(await context.suite.complianceModule.canComplianceBind(await context.suite.compliance.getAddress())).to.be.false;
        });
      });

      describe('when compliance preset status is true', () => {
        it('should return true', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          const complianceModule = await ethers.deployContract('MaxOwnershipModule');

          await complianceModule
            .connect(context.accounts.deployer)
            .preSetModuleState(await context.suite.compliance.getAddress(), context.accounts.aliceWallet.address, 100);

          expect(await complianceModule.canComplianceBind(await context.suite.compliance.getAddress())).to.be.true;
        });
      });
    });

    describe('when token totalSupply is zero', () => {
      it('should return true', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        const complianceModule = await ethers.deployContract('MaxOwnershipModule');

        expect(await complianceModule.canComplianceBind(await context.suite.compliance.getAddress())).to.be.true;
      });
    });
  });

  describe('.setMaxPercentage', () => {
    describe('when calling directly', () => {
      it('should revert', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);

        await expect(context.suite.complianceModule.setMaxPercentage(100)).to.revertedWith('only bound compliance can call');
      });
    });

    describe('when calling via compliance', () => {
      it('should set max percentage', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);

        const tx = await context.suite.compliance.callModuleFunction(
          new ethers.Interface(['function setMaxPercentage(uint16 _max)']).encodeFunctionData('setMaxPercentage', [1000]), // 10%
          await context.suite.complianceModule.getAddress(),
        );

        await expect(tx).to.emit(context.suite.complianceModule, 'MaxPercentageSet').withArgs(await context.suite.compliance.getAddress(), 1000);
      });
    });
  });

  describe('.preSetModuleState', () => {
    describe('when calling directly', () => {
      it('should revert', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        await expect(
          context.suite.complianceModule
            .connect(context.accounts.aliceWallet)
            .preSetModuleState(await context.suite.compliance.getAddress(), context.accounts.aliceWallet.address, 100),
        ).to.be.revertedWithCustomError(context.suite.complianceModule, `OnlyComplianceOwnerCanCall`);
      });
    });

    describe('when calling via deployer', () => {
      describe('when compliance already bound', () => {
        it('should revert', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          await expect(
            context.suite.complianceModule
              .connect(context.accounts.deployer)
              .preSetModuleState(await context.suite.compliance.getAddress(), context.accounts.aliceWallet.address, 100),
          ).to.be.revertedWithCustomError(context.suite.complianceModule, `TokenAlreadyBound`);
        });
      });

      describe('when compliance is not yet bound', () => {
        it('should preset', async () => {
          const context = await loadFixture(deployComplianceFixture);
          const complianceModule = await ethers.deployContract('MaxOwnershipModule');

          const tx = await complianceModule
            .connect(context.accounts.deployer)
            .preSetModuleState(await context.suite.compliance.getAddress(), context.accounts.aliceWallet.address, 100);

          await expect(tx)
            .to.emit(complianceModule, 'IDBalancePreSet')
            .withArgs(await context.suite.compliance.getAddress(), context.accounts.aliceWallet.address, 100);
        });
      });
    });
  });

  describe('.presetCompleted', () => {
    describe('when calling directly', () => {
      it('should revert', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        await expect(
          context.suite.complianceModule.connect(context.accounts.aliceWallet).presetCompleted(await context.suite.compliance.getAddress()),
        ).to.be.revertedWithCustomError(context.suite.complianceModule, `OnlyComplianceOwnerCanCall`);
      });
    });

    describe('when calling via deployer', () => {
      it('should update preset status as true', async () => {
        const context = await loadFixture(deployComplianceFixture);
        const complianceModule = await ethers.deployContract('MaxOwnershipModule');

        await complianceModule.connect(context.accounts.deployer).presetCompleted(await context.suite.compliance.getAddress());

        expect(await complianceModule.canComplianceBind(await context.suite.compliance.getAddress())).to.be.true;
      });
    });
  });

  describe('.batchPreSetModuleState', () => {
    describe('when calling directly', () => {
      it('should revert', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        await expect(
          context.suite.complianceModule
            .connect(context.accounts.aliceWallet)
            .batchPreSetModuleState(await context.suite.compliance.getAddress(), [context.accounts.aliceWallet.address], [100]),
        ).to.be.revertedWithCustomError(context.suite.complianceModule, `OnlyComplianceOwnerCanCall`);
      });
    });

    describe('when calling via deployer', () => {
      describe('when _id array is empty', () => {
        it('should revert', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          await expect(
            context.suite.complianceModule.connect(context.accounts.deployer).batchPreSetModuleState(await context.suite.compliance.getAddress(), [], []),
          ).to.be.revertedWithCustomError(context.suite.complianceModule, `InvalidPresetValues`);
        });
      });

      describe('when the lengths of the _id and _balance arrays are not equal', () => {
        it('should revert', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          await expect(
            context.suite.complianceModule
              .connect(context.accounts.deployer)
              .batchPreSetModuleState(
                await context.suite.compliance.getAddress(),
                [context.accounts.aliceWallet.address, context.accounts.bobWallet.address],
                [100],
              ),
          ).to.be.revertedWithCustomError(context.suite.complianceModule, `InvalidPresetValues`);
        });
      });

      describe('when compliance already bound', () => {
        it('should revert', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          await expect(
            context.suite.complianceModule
              .connect(context.accounts.deployer)
              .batchPreSetModuleState(await context.suite.compliance.getAddress(), [context.accounts.aliceWallet.address], [100]),
          ).to.be.revertedWithCustomError(context.suite.complianceModule, `TokenAlreadyBound`);
        });
      });

      describe('when compliance is not yet bound', () => {
        it('should preset', async () => {
          const context = await loadFixture(deployComplianceFixture);
          const complianceModule = await ethers.deployContract('MaxOwnershipModule');

          const tx = await complianceModule
            .connect(context.accounts.deployer)
            .batchPreSetModuleState(
              await context.suite.compliance.getAddress(),
              [context.accounts.aliceWallet.address, context.accounts.bobWallet.address],
              [100, 200],
            );

          await expect(tx)
            .to.emit(complianceModule, 'IDBalancePreSet')
            .withArgs(await context.suite.compliance.getAddress(), context.accounts.aliceWallet.address, 100)
            .to.emit(complianceModule, 'IDBalancePreSet')
            .withArgs(await context.suite.compliance.getAddress(), context.accounts.bobWallet.address, 200);
        });
      });
    });
  });

  describe('.moduleTransferAction', () => {
    describe('when calling directly', () => {
      it('should revert', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        const from = context.accounts.aliceWallet.address;
        const to = context.accounts.bobWallet.address;

        await expect(context.suite.complianceModule.moduleTransferAction(from, to, 10)).to.revertedWith('only bound compliance can call');
      });
    });

    describe('when calling via compliance', () => {
      describe('when value exceeds the max percentage', () => {
        it('should revert', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          const from = context.accounts.aliceWallet.address;
          const to = context.accounts.bobWallet.address;
          const decimals = await context.suite.token.decimals();

          // mint one thousand tokens to create total supply
          await context.suite.token
            .connect(context.accounts.tokenAgent)
            .mint(context.accounts.aliceWallet, 1000n * 10n ** decimals);
          
          const twentyBP = 20n * 10n ** 2n;
          const oneHundredBP = 100n * 10n ** 2n;

          // set 100% as the max percentage of ownership in order to mint for the sender
          await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function setMaxPercentage(uint16 _max)']).encodeFunctionData('setMaxPercentage', [oneHundredBP]),
            await context.suite.complianceModule.getAddress(),
          );

          // mint total supply (1000 tokens) to the from address
          await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function moduleMintAction(address _to, uint256 _value)']).encodeFunctionData('moduleMintAction', [
              from,
              await context.suite.token.totalSupply(),
            ]),
            await context.suite.complianceModule.getAddress(),
          );

          // set 20% as the max percentage of ownership
          await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function setMaxPercentage(uint16 _max)']).encodeFunctionData('setMaxPercentage', [twentyBP]),
            await context.suite.complianceModule.getAddress(),
          );

           // transfer 200 (20% of total suply) tokens to the "to" address 
           await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function moduleTransferAction(address _from, address _to, uint256 _value)']).encodeFunctionData(
              'moduleTransferAction',
              [from, to, 200n * 10n ** decimals],
            ),
            await context.suite.complianceModule.getAddress(),
          );
          
          // attemp to transfer 100 token to "to" address (this exceeds 20%)
          await expect(
            context.suite.compliance.callModuleFunction(
              new ethers.Interface(['function moduleTransferAction(address _from, address _to, uint256 _value)']).encodeFunctionData(
                'moduleTransferAction',
                [from, to, 100n * 10n ** decimals],
              ),
              await context.suite.complianceModule.getAddress(),
            ),
          ).to.be.revertedWithCustomError(context.suite.complianceModule, `MaxOwnershipExceeded`);

         
        });
      });

      describe('when value does not exceed the max ownership', () => {
        it('should update receiver and sender balances', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          const from = context.accounts.aliceWallet.address;
          const to = context.accounts.bobWallet.address;
          const decimals = await context.suite.token.decimals();
          const senderIdentity = await context.suite.identityRegistry.identity(context.accounts.aliceWallet.address);
          const receiverIdentity = await context.suite.identityRegistry.identity(context.accounts.bobWallet.address);

          // mint one thousand tokens to create total supply
          await context.suite.token
            .connect(context.accounts.tokenAgent)
            .mint(context.accounts.aliceWallet, 1000n * 10n ** decimals);
          
          const twentyBP = 20n * 10n ** 2n;

          // set maxPercentage 20%
          await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function setMaxPercentage(uint16 _max)']).encodeFunctionData('setMaxPercentage', [twentyBP]),
            await context.suite.complianceModule.getAddress(),
          );

          // call moduleMintAction with 200 hundred tokens (20%)
          await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function moduleMintAction(address _to, uint256 _value)']).encodeFunctionData('moduleMintAction', [
              from,
              200n * 10n ** decimals,
            ]),
            await context.suite.complianceModule.getAddress(),
          );

          // transfer 150 tokens (less then 20%)
          await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function moduleTransferAction(address _from, address _to, uint256 _value)']).encodeFunctionData(
              'moduleTransferAction',
              [from, to, 150n * 10n ** decimals],
            ),
            await context.suite.complianceModule.getAddress(),
          );

          const senderBalance = await context.suite.complianceModule.getIDBalance(await context.suite.compliance.getAddress(), senderIdentity);
          expect(senderBalance).to.be.eq(50n * 10n ** decimals,);

          const receiverBalance = await context.suite.complianceModule.getIDBalance(await context.suite.compliance.getAddress(), receiverIdentity);
          expect(receiverBalance).to.be.eq(150n * 10n ** decimals,);
        });
      });
    });
  });

  describe('.moduleMintAction', () => {
    describe('when calling directly', () => {
      it('should revert', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        const to = context.accounts.bobWallet.address;

        await expect(context.suite.complianceModule.moduleMintAction(to, 10)).to.revertedWith('only bound compliance can call');
      });
    });

    describe('when calling via compliance', () => {
        it('should update minter balance', async () => {
          const context = await loadFixture(deployMaxOwnershipFullSuite);
          const to = context.accounts.aliceWallet.address;
          const receiverIdentity = await context.suite.identityRegistry.identity(context.accounts.aliceWallet.address);

          const decimals = await context.suite.token.decimals();
          const twenty = 20n * 1n ** decimals;
          const oneHundred = 100n * 1n ** decimals;

          // mint one thousand tokens to create total supply
          await context.suite.token
            .connect(context.accounts.tokenAgent)
            .mint(context.accounts.aliceWallet, 1000n * 1n ** decimals);

          await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function setMaxPercentage(uint16 _max)']).encodeFunctionData('setMaxPercentage', [twenty]),
            await context.suite.complianceModule.getAddress(),
          );

          await context.suite.compliance.callModuleFunction(
            new ethers.Interface(['function moduleMintAction(address _to, uint256 _value)']).encodeFunctionData('moduleMintAction', [to, oneHundred]),
            await context.suite.complianceModule.getAddress(),
          );

          const receiverBalance = await context.suite.complianceModule.getIDBalance(await context.suite.compliance.getAddress(), receiverIdentity);
          expect(receiverBalance).to.be.eq(oneHundred);
        });
    });
  });

  describe('.moduleBurnAction', () => {
    describe('when calling directly', () => {
      it('should revert', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        const from = context.accounts.bobWallet.address;

        await expect(context.suite.complianceModule.moduleBurnAction(from, 10)).to.revertedWith('only bound compliance can call');
      });
    });

    describe('when calling via compliance', () => {
      it('should update sender balance', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        const from = context.accounts.aliceWallet.address;
        const senderIdentity = await context.suite.identityRegistry.identity(context.accounts.aliceWallet.address);

        const decimals = await context.suite.token.decimals();
        const twenty = 20n * 1n ** decimals;
        const oneHundred = 100n * 1n ** decimals;

        // mint one thousand tokens to create total supply
        await context.suite.token
          .connect(context.accounts.tokenAgent)
          .mint(context.accounts.aliceWallet, 1000n * 1n ** decimals);

        await context.suite.compliance.callModuleFunction(
          new ethers.Interface(['function setMaxPercentage(uint16 _max)']).encodeFunctionData('setMaxPercentage', [twenty]),
          await context.suite.complianceModule.getAddress(),
        );

        await context.suite.compliance.callModuleFunction(
          new ethers.Interface(['function moduleMintAction(address _to, uint256 _value)']).encodeFunctionData('moduleMintAction', [from, oneHundred]),
          await context.suite.complianceModule.getAddress(),
        );

        await context.suite.compliance.callModuleFunction(
          new ethers.Interface(['function moduleBurnAction(address _from, uint256 _value)']).encodeFunctionData('moduleBurnAction', [from, twenty]),
          await context.suite.complianceModule.getAddress(),
        );

        const senderBalance = await context.suite.complianceModule.getIDBalance(await context.suite.compliance.getAddress(), senderIdentity);
        expect(senderBalance).to.be.eq(oneHundred - twenty);
      });
    });
  });

  describe('.moduleCheck', () => {
      it('should always return true', async () => {
        const context = await loadFixture(deployMaxOwnershipFullSuite);
        const to = context.accounts.bobWallet.address;
        const from = context.accounts.aliceWallet.address;

        const decimals = await context.suite.token.decimals();
        const oneHundred = 100n * 1n ** decimals;        

        expect(await context.suite.complianceModule.moduleCheck(from, to, oneHundred, await context.suite.compliance.getAddress())).to.be.equal(true);
      });    
  });
});
