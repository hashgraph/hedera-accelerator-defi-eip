// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./HTSToken.sol";

contract HTSTokenFactory {
    // Used salt => deployed Tokens
    mapping(bytes32 => address) public tokenDeployed;

    // emited when an exchagne is deployed
    event TokenDeployed(address token, address deployer);

    /**
     * @dev Deploys a token using CREATE2 opcode.
     *
     * @param name string
     * @param symbol string
     * @return token address of the deployed Token.
     */
    function deployToken(string memory name, string memory symbol) external payable returns (address token) {
        bytes32 salt = bytes32(keccak256(abi.encodePacked(msg.sender, name, symbol)));
        require(tokenDeployed[salt] == address(0), "Token already deployed");

        token = _deployToken(salt, name, symbol);

        tokenDeployed[salt] = token;

        emit TokenDeployed(token, msg.sender);
    }

    /**
     * @dev Creates deployment data for the CREATE2 opcode.
     *
     * @return The the address of the contract created.
     */
    function _deployToken(bytes32 salt, string memory name, string memory symbol) private returns (address) {
        bytes memory _code = type(HTSToken).creationCode;
        bytes memory _constructData = abi.encode(name, symbol);
        bytes memory deploymentData = abi.encodePacked(_code, _constructData);
        return _deploy(salt, deploymentData);
    }

    /**
     * @dev Deploy function with create2 opcode call.
     *
     * @return The the address of the contract created.
     */
    function _deploy(bytes32 salt, bytes memory bytecode) private returns (address) {
        address addr;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let encoded_data := add(0x20, bytecode) // load initialization code.
            let encoded_size := mload(bytecode) // load init code's length.
            addr := create2(callvalue(), encoded_data, encoded_size, salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return addr;
    }
}
