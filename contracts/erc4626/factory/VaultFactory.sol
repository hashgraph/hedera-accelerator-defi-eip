// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {BasicVault} from "../BasicVault.sol";
import {FeeConfiguration} from "../../common/FeeConfiguration.sol";
import {IOwnable} from "./interfaces/IOwnable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Vault Factory
 *
 * The contract which allows to deploy Vaults with different parameters
 * and track contract addresses.
 */
contract VaultFactory is Ownable, IVaultFactory, ERC165 {
    // Used salt => deployed Vault
    mapping(string => address) public vaultDeployed;

    /**
     * @dev Initializes contract with passed parameters.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Deploys a Vault using CREATE2 opcode.
     * @notice It's required to send at least 12 HBAR for token creation and associations.
     *
     * @param salt The CREATE2 salt.
     * @param vaultDetails The Vault parameters.
     * @param feeConfig The fee configuration setup for Vault.
     * @return vault The address of the deployed Vault.
     */
    function deployVault(
        string calldata salt,
        VaultDetails calldata vaultDetails,
        FeeConfiguration.FeeConfig calldata feeConfig
    ) external payable returns (address vault) {
        require(vaultDeployed[salt] == address(0), "VaultFactory: Vault already deployed");
        require(vaultDetails.stakingToken != address(0), "VaultFactory: Invalid staking token");
        require(vaultDetails.vaultRewardController != address(0), "VaultFactory: Invalid reward controller address");
        require(vaultDetails.feeConfigController != address(0), "VaultFactory: Invalid fee controller address");

        vault = _deployVault(salt, vaultDetails, feeConfig);

        vaultDeployed[salt] = vault;

        IOwnable(vault).transferOwnership(msg.sender);

        emit VaultDeployed(
            vault,
            vaultDetails.stakingToken,
            vaultDetails.shareTokenName,
            vaultDetails.shareTokenSymbol
        );
    }

    /**
     * Gen Salt string for CREATE2
     * @param deployer address
     * @param nonce uint256
     * @param token address
     */
    function generateSalt(
        address deployer,
        address token,
        uint256 nonce
    ) external pure returns (string memory) {
        // Convert the deployer and token addresses to hexadecimal strings,
        // and the nonce to a decimal string.
        return string(
            abi.encodePacked(
                Strings.toHexString(uint256(uint160(deployer)), 20),
                Strings.toHexString(uint256(uint160(token)), 20),
                Strings.toString(nonce)
            )
        );
    }

    /**
     * @dev Creates deployment data for the CREATE2 opcode.
     *
     * @return The the address of the contract created.
     */
    function _deployVault(
        string calldata salt,
        VaultDetails calldata vaultDetails,
        FeeConfiguration.FeeConfig calldata feeConfig
    ) private returns (address) {
        bytes memory _code = type(BasicVault).creationCode;
        bytes memory _constructData = abi.encode(
            vaultDetails.stakingToken,
            vaultDetails.shareTokenName,
            vaultDetails.shareTokenSymbol,
            feeConfig.receiver,
            feeConfig.token,
            feeConfig.feePercentage,
            vaultDetails.vaultRewardController,
            vaultDetails.feeConfigController
        );

        bytes memory deploymentData = abi.encodePacked(_code, _constructData);
        return _deploy(salt, deploymentData);
    }

    /**
     * @dev Deploy function with create2 opcode call.
     *
     * @return The the address of the contract created.
     */
    function _deploy(string calldata salt, bytes memory bytecode) private returns (address) {
        bytes32 saltBytes = bytes32(keccak256(abi.encodePacked(salt)));
        address addr;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let encoded_data := add(0x20, bytecode) // load initialization code.
            let encoded_size := mload(bytecode) // load init code's length.
            addr := create2(callvalue(), encoded_data, encoded_size, saltBytes)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return addr;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return interfaceId == type(IVaultFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
