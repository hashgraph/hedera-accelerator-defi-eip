// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title Ownable
 *
 * @notice The interface helps to transfer the contract ownership
 * after deployments from the Vault Factory.
 */
interface IOwnable {
    /**
     * @notice Transfers ownership of a contract to a new owner.
     *
     * @param newOwner The address of a new owner.
     */
    function transferOwnership(address newOwner) external;
}
