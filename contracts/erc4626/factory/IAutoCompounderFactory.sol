// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title AutoCompounder Factory
 *
 * The contract which allows to deploy AutoCompounder contracts with different parameters
 * and track contract addresses.
 */
interface IAutoCompounderFactory {
    /**
     * @notice AutoCompounderDeployed event.
     * @dev Emitted after AutoCompounder deployment.
     *
     * @param autoCompounder The address of the deployed AutoCompounder.
     * @param name The name of the deployed aToken.
     * @param symbol The symbol of the deployed aToken.
     */
    event AutoCompounderDeployed(address indexed autoCompounder, string name, string symbol);

    // AutoCompounder details struct
    struct AutoCompounderDetails {
        address uniswapV2Router;
        address vault;
        address usdc;
        string aTokenName;
        string aTokenSymbol;
    }

    /**
     * @dev Deploys an AutoCompounder using CREATE2 opcode.
     *
     * @param salt The CREATE2 salt.
     * @param autoCompounderDetails The AutoCompounder parameters.
     * @return autoCompounder The address of the deployed AutoCompounder.
     */
    function deployAutoCompounder(
        string memory salt,
        AutoCompounderDetails calldata autoCompounderDetails
    ) external payable returns (address autoCompounder);
}
