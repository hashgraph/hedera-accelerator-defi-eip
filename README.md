# 🏗️ Hedera RWA DeFi Accelerator – Smart Contracts

This is the smart contract suite powering **the Hedera RWA/DeFi Accelerator** — a modula and extensible tokenized real estate system built with Hedera and Ethereum-compatible standards.

This monorepo defines the full logic of tokenized building creation, ownership, liquidity, governance, and yield. It is designed to be composable, regulatory-friendly, and performant enough to serve as a foundation for the future of Real World Asset (RWA) management on-chain.

---

## 🧠 Architecture Overview

Each **Building** is a self-contained on-chain entity with:

- A unique **NFT identity** and metadata (ERC-721 / HTS)
- A fungible **ownership token** (ERC-3643 w/ compliance layers)
- An optional **vault** for real-yield distribution (ERC-4626 / ERC-7540)
- Governance support via **proposals and DAO voting**
- Liquidity interfaces (LBPs, AMMs, Uniswap)

---

## 🧾 Key Modules

### 🏢 `buildings/`
- `BuildingFactory.sol` – deploys buildings via Beacon proxies
- `Building.sol` / `BuildingBase.sol` – NFT metadata, token minting, treasury linking
- Extensions:
  - `BuildingAudit.sol` – audit data
  - `BuildingLiquidityPool.sol` – LP token interfaces

### 🧩 `erc3643/`
- Fully compliant share tokens w/ modular transfer restrictions
- `compliance/`, `proxy/`, and `registry/` folders define the full ERC-3643 stack
- Supports geo-fencing, whitelisting, investor caps, and other transfer modules

### 🧱 `erc721/`
- `ERC721Metadata.sol` – core metadata NFT for real estate
- `ERC721MetadataHTS.sol` – HTS-compatible NFT contract for high-throughput deployments
- Metadata includes on-chain key-value storage and IPFS-backed JSON

### 💰 `erc4626/` & `erc7540/`
- Vaults for managing deposits, yield, and liquidity streaming
- `AutoCompounder.sol` for reinvesting yield
- `VaultFactory.sol` to deploy and configure vaults

### 🔐 `onchainid/`
- Identity system based on OnChainID (KYC/KYB)
- Includes identity creation, claim issuers, verifiers, and proxies

### 🔄 `exchange/` & `orderbook/`
- AMM (`OneSidedExchange.sol`) and traditional orderbook (`Orderbook.sol`)

### 💼 `treasury/`
- `Treasury.sol` – receives building income
- `VaultMock.sol` and `ERC20Mock.sol` for testing

---

## 🏗️ Key Design Patterns

- **Beacon Proxy Deployments** – for upgradable buildings via `BuildingFactory.sol`
- **Factory Pattern** – used across vaults, slices, identity, and tokens
- **Modular Compliance** – plug-and-play restrictions (ERC-3643)
- **On-chain Metadata + IPFS** – small critical fields on-chain, full JSON off-chain
- **Protocol-Owned Liquidity** – buildings can own LP positions or vaults

---

## 🧪 Getting Started

```bash
npx hardhat compile
```

---

## 📚 Resources

- [How We Tokenize Buildings](https://hedera.com/blog/how-can-we-model-a-building-in-web3)
- [ERC-3643 Standard](https://github.com/erc3643/standard)
- [Hedera Token Service Docs](https://hedera.com/hts)
- [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626)
- [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540)

---

## ⚠️ Disclaimer

These contracts are experimental and unaudited. Do not use in production without proper due diligence and formal verification.

* no warranties.
* this code is 'in progress', and is intended for demonstration and/or start of your project. you need to do your own QA & Audits before using this.

---

## 🤝 Contributions

We welcome PRs, optimizations, or new contract modules that can enhance tokenized RWAs. Please open issues for bugs or suggestions.

---

Happy Building 🚀
