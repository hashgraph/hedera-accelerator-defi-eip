// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ISliceFactory} from "./interfaces/ISliceFactory.sol";
import {Slice} from "../Slice.sol";
import {IOwnable} from "./interfaces/IOwnable.sol";

/**
 * @title Slice Factory
 *
 * The contract which allows to deploy Slices with different parameters
 * and track contract addresses.
 */
contract SliceFactory is ISliceFactory, Ownable, ERC165 {
    // Used salt => deployed Slice
    mapping(string => address) public sliceDeployed;

    /**
     * @dev Initializes contract with passed parameters.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Deploys a Slice using CREATE2 opcode.
     * @notice It's required to send at least 12 HBAR for token creation and associations.
     *
     * @param salt The CREATE2 salt.
     * @param sliceDetails The Slice parameters.
     * @return slice The address of the deployed Slice.
     */
    function deploySlice(string calldata salt, SliceDetails calldata sliceDetails) external returns (address slice) {
        require(sliceDeployed[salt] == address(0), "SliceFactory: Slice already deployed");
        require(sliceDetails.pyth != address(0), "SliceFactory: Invalid Pyth oracle address");
        require(sliceDetails.uniswapRouter != address(0), "SliceFactory: Invalid Uniswap Router address");
        require(sliceDetails.usdc != address(0), "SliceFactory: Invalid USDC address");

        slice = _deploySlice(salt, sliceDetails);

        IOwnable(slice).transferOwnership(msg.sender);

        emit SliceDeployed(slice, sliceDetails.pyth, sliceDetails.uniswapRouter, sliceDetails.usdc);
    }

    /**
     * @dev Creates deployment data for the CREATE2 opcode.
     *
     * @return The the address of the contract created.
     */
    function _deploySlice(string calldata salt, SliceDetails calldata sliceDetails) private returns (address) {
        bytes memory _code = type(Slice).creationCode;
        bytes memory _constructData = abi.encode(sliceDetails.pyth, sliceDetails.uniswapRouter, sliceDetails.usdc);

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
        return interfaceId == type(ISliceFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
