// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAutoCompounderFactory} from "./IAutoCompounderFactory.sol";
import {AutoCompounder} from "../AutoCompounder.sol";
import {IOwnable} from "./IOwnable.sol";

/**
 * @title AutoCompounder Factory
 *
 * The contract which allows to deploy AutoCompounder with different parameters
 * and track contract addresses.
 */
contract AutoCompounderFactory is IAutoCompounderFactory, Ownable, ERC165 {
    // Used salt => deployed AutoCompounder
    mapping(string => address) public autoCompounderDeployed;

    /**
     * @dev Initializes contract with passed parameters.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Deploys an AutoCompounder using CREATE2 opcode.
     * @notice It's required to send at least 18 HBAR for token creation and associations.
     *
     * @param salt The CREATE2 salt.
     * @param autoCompounderDetails The AutoCompounder parameters.
     * @return autoCompounder The address of the deployed AutoCompounder.
     */
    function deployAutoCompounder(
        string calldata salt,
        AutoCompounderDetails calldata autoCompounderDetails
    ) external payable returns (address autoCompounder) {
        require(autoCompounderDeployed[salt] == address(0), "AutoCompounder already deployed");
        require(autoCompounderDetails.uniswapV2Router != address(0), "Invalid Uniswap Router address");
        require(autoCompounderDetails.vault != address(0), "Invalid Vault address");
        require(autoCompounderDetails.usdc != address(0), "Invalid USDC address");

        autoCompounder = _deployAutoCompounder(salt, autoCompounderDetails);

        autoCompounderDeployed[salt] = autoCompounder;

        IOwnable(autoCompounder).transferOwnership(msg.sender);

        emit AutoCompounderDeployed(
            autoCompounder,
            autoCompounderDetails.aTokenName,
            autoCompounderDetails.aTokenSymbol
        );
    }

    /**
     * @dev Creates deployment data for the CREATE2 opcode.
     *
     * @return The the address of the contract created.
     */
    function _deployAutoCompounder(
        string calldata salt,
        AutoCompounderDetails calldata autoCompounderDetails
    ) private returns (address) {
        bytes memory _code = type(AutoCompounder).creationCode;
        bytes memory _constructData = abi.encode(
            autoCompounderDetails.uniswapV2Router,
            autoCompounderDetails.vault,
            autoCompounderDetails.usdc,
            autoCompounderDetails.aTokenName,
            autoCompounderDetails.aTokenSymbol
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
        return interfaceId == type(IAutoCompounderFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
