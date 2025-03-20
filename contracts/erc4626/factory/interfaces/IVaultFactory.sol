// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeConfiguration} from "../../../common/FeeConfiguration.sol";

/**
 * @title Vault Factory
 *
 * The contract which allows to deploy Vaults with different parameters
 * and track contract addresses.
 */
interface IVaultFactory {
    /**
     * @notice VaultDeployed event.
     * @dev Emitted after Vault deployment.
     *
     * @param vault The address of the deployed Vault.
     * @param asset The address of the related underlying asset.
     * @param name The name of the deployed Vault.
     * @param symbol The symbol of the deployed Vault.
     */
    event VaultDeployed(address indexed vault, address indexed asset, string name, string symbol);

    // Vault details struct
    struct VaultDetails {
        address stakingToken;
        string shareTokenName;
        string shareTokenSymbol;
        address vaultRewardController;
        address feeConfigController;
    }

    /**
     * @dev Deploys a Vault using CREATE2 opcode.
     *
     * @param salt The CREATE2 salt.
     * @param vaultDetails The Vault parameters.
     * @param feeConfig The fee configuration setup for Vault.
     * @return vault The address of the deployed Vault.
     */
    function deployVault(
        string memory salt,
        VaultDetails calldata vaultDetails,
        FeeConfiguration.FeeConfig calldata feeConfig
    ) external payable returns (address vault);

    /**
     * Generate salt
     * @param deployer address
     * @param token address
     * @param nonce uint256
     */
    function generateSalt(
        address deployer,
        address token,
        uint256 nonce
    ) external pure returns (string memory);
}
