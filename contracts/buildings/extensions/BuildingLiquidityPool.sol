// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {IUniswapV2Factory, IUniswapV2Pair, IUniswapV2Router02} from "../interface/UniswapInterface.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BuildingLiquidityPool
/// @author Hashgraph
/// @notice This contract uses namespaced storage see https://docs.openzeppelin.com/contracts/5.x/upgradeable#namespaced_storage
abstract contract BuildingLiquidityPool is Initializable{
    /// @custom:storage-location erc7201:hashgraph.buildings.BuildingLiquidityPool
    struct BuildingLiquidityPoolStorage {
        address uniswapRouter;
        address uniswapFactory;
    }

    //keccak256(abi.encode(uint256(keccak256("hashgraph.buildings.BuildingLiquidityPool")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BuildingLiquidityPoolStorageLocation = 0x75fd97eeafae39525b32773f2af3e4b201521c02695ece8bd2fe94e4c5024f00;

    function _getBuildingLiquidityPoolStorage() private pure returns (BuildingLiquidityPoolStorage storage $) {
        assembly {
            $.slot := BuildingLiquidityPoolStorageLocation
        }
    }

    function __Liquidity_init (address _uniswapRouter, address _uniswapFactory) internal onlyInitializing {
        BuildingLiquidityPoolStorage storage $ = _getBuildingLiquidityPoolStorage();
        
        $.uniswapRouter = _uniswapRouter;
        $.uniswapFactory = _uniswapFactory;
    }

    function getUniswapRouter() public view returns(address) {
        BuildingLiquidityPoolStorage storage $ = _getBuildingLiquidityPoolStorage();
        return $.uniswapRouter;
    }

    function getUniswapFactory() public view returns(address) {
        BuildingLiquidityPoolStorage storage $ = _getBuildingLiquidityPoolStorage();
        return $.uniswapFactory;
    }

    function _addLiquidityToPool(
        address _tokenA, 
        address _tokenB, 
        uint256 _tokenAAmount, 
        uint256 _tokenBAmount
    ) internal returns(uint amountA, uint amountB, uint liquidity, address pair) {
        BuildingLiquidityPoolStorage storage $ = _getBuildingLiquidityPoolStorage();

        pair = IUniswapV2Factory($.uniswapFactory).getPair(_tokenA, _tokenB);
        
        if (pair == address(0)){
            pair = IUniswapV2Factory($.uniswapFactory).createPair(_tokenA, _tokenB);
        }

        IERC20(_tokenA).approve(address($.uniswapRouter), _tokenAAmount);
        IERC20(_tokenB).approve(address($.uniswapRouter), _tokenBAmount);
        
        (
            amountA, // The actual amounts of tokenA that were added to the pool.
            amountB, // The actual amounts of tokenB that were added to the pool.
            liquidity // The number of liquidity tokens (LP tokens) minted and sent to the to address.
        ) = IUniswapV2Router02($.uniswapRouter).addLiquidity(
            _tokenA, // The addresses of the tokenA you want to add to the liquidity pool
            _tokenB, // The addresses of the tokenB you want to add to the liquidity pool
            _tokenAAmount, // amountADesired The amounts of tokenA you wish to deposit into the liquidity pool
            _tokenBAmount, // amountBDesired The amounts of tokenB you wish to deposit into the liquidity pool
            _tokenAAmount, // The minimum amounts of tokenA you are willing to add. (These serve as a safeguard against large price slippage)
            _tokenBAmount, // The minimum amounts of tokenB you are willing to add. (These serve as a safeguard against large price slippage)
            address(this), // The address that will receive the liquidity pool (LP) tokens
            block.timestamp + 300 // A timestamp (in seconds) after which the transaction will revert if it hasn't been executed.  prevents front-running 
        );
    }

    function createLiquidityPair(address tokenA, address tokenB) public returns (address pair) {
        BuildingLiquidityPoolStorage storage $ = _getBuildingLiquidityPoolStorage();
        pair = IUniswapV2Factory($.uniswapFactory).createPair(tokenA, tokenB);
    }
}
