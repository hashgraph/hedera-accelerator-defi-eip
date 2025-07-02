# 🏗️ Building Module – RWA Accelerator DeFi Suite on Hedera

This folder contains the smart contracts related to on-chain buildings, representing tokenized real-world physical assets deployed on the Hedera EVM.

These contracts are part of the broader **Hedera RWA DeFi Accelerator** initiative.

---

## 📚 Overview

The `building` module implements a factory-based pattern to deploy modular, governable, and compliant tokenized buildings. Each deployed building bundle includes:

- An ERC3643-compliant token (ownership representation)
- A dedicated ERC4626 vault (asset management)
- An OpenZeppelin Governor contract (governance)
- A treasury contract (fund flows)
- An identity system using OnchainID (compliance)

Each module is upgradeable and designed for composability and regulation-ready asset deployment.

---

## 🧱 Contracts

| Contract                  | Purpose |
|---------------------------|---------|
| **BuildingFactory.sol**     | Deploys complete building suites with all linked modules and configurations. |
| **BuildingVault.sol**       | ERC4626 vault for yield strategies, rental income, or building-linked assets. |
| **BuildingToken.sol**       | ERC3643-compliant token representing building ownership. |
| **BuildingGovernor.sol**    | Configurable on-chain governance based on OpenZeppelin Governor. |
| **BuildingTreasury.sol**    | Manages ETH/HBAR/token flow for operational treasury management. |
| **BuildingAutoCompounder.sol**    | Automates yield compounding for vaults, redirecting returns per configured strategy |


---

## 🧬 Architecture

Each building is deployed through the `BuildingFactory`, which:

1. Generates identity contracts (OnchainID) for all involved parties
2. Deploys the ERC3643 token, vault, governor, and treasury modules
3. Assigns all required roles and configurations
4. Links the entire setup under a unique building address

> 📦 Contracts are upgradeable via Beacon Proxies for long-term modularity and maintainability.

---

## 🛡️ Compliance Layer

Each `BuildingToken` integrates with the ERC3643 suite:

- **IdentityRegistry**
- **ClaimTopicsRegistry**
- **TrustedIssuersRegistry**
- **Compliance** module

These ensure that only KYC-verified and regulatorily compliant users can hold or transfer building tokens.

---

## 🗳️ Governance

Each building is governed by its own instance of `BuildingGovernor`, allowing token holders to:

- Propose and vote on parameter changes
- Approve treasury spending
- Upgrade modules or roles

Governance is instantiated with configurable settings such as voting delay, voting period, quorum, and proposal thresholds.

---

## 🚀 Deployment

To deploy a new building suite:

```solidity
BuildingFactory factory = BuildingFactory(factoryAddress);
factory.newBuilding(NewBuildingDetails calldata details);
```
### Parameters include:

| Param                  | Purpose |
|---------------------------|---------|
| **string** tokenURI     | IPFS URI of the building's metadata |
| **string** tokenName     | ERC3643 Building Token name|
| **string** tokenSymbol     | ERC3643 Building Token symbol |
| **uint8** tokenDecimals     | ERC3643 Building Token decimals |
| **uint256** tokenMintAmount     | Initial amount of ERC3643 tokens to mint to the sender |
| **uint256** treasuryReserveAmount     | High-level watermark of USDC held as a reserve in the treasury |
| **uint256** treasuryNPercent     | Percentage (in basis points) of vault yield to be transferred to the treasury reserve. Example: 1000 = 10% |
| **string** governanceName     | Name for the Building Governor contract |
| **string** vaultShareTokenName     | ERC4626 Vault Token name |
| **string** vaultShareTokenSymbol     | ERC4626 Vault Token symbol |
| **address** vaultFeeReceiver     | Address to receive collected ERC4626 vault fees |
| **address** vaultFeeToken     | ERC4626 vault fee token address |
| **uint256** vaultFeePercentage     | ERC4626 vault fee percentage |
| **uint32** vaultCliff     | Cliff period (in seconds) before vault shares can be unlocked or withdrawn |
| **uint32** vaultUnlockDuration     | Duration (in seconds) over which shares are linearly unlocked |
| **string** aTokenName     | Auto Compounder token name |
| **string** aTokenSymbol     | Auto Compounder Token symbol |


All modules are linked, configured, and role-assigned during deployment by the factory contract.

---

## 🧪 Testing

All tests are located under:

```
/test/building/
```


### Running Tests

With Hardhat:

```bash
npx hardhat test test/building/
```

---
