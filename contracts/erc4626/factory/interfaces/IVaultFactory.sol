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
     * @param name The name of the deployed Vault.
     * @param symbol The symbol of the deployed Vault.
     */
    event VaultDeployed(address indexed vault, string name, string symbol);

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
     * @dev Checks if Vault is available.
     *
     * @return The bool flag of vault's availability.
     */
    function isVaultAvailable(address vault) external view returns (bool);
}
