// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {BuildingBase} from './BuildingBase.sol';
import {BuildingLiquidityPool} from "./extensions/BuildingLiquidityPool.sol";
import {BuildingAudit} from "./extensions/BuildingAudit.sol";

contract Building is BuildingBase, BuildingLiquidityPool, BuildingAudit {

    function initialize (
        bytes32 _salt,
        address _uniswapRouter, 
        address _uniswapFactory,
        address _nftAddress
    ) external payable initializer {
        __Ownable_init(_msgSender());
        __Building_init();
        __Liquidity_init(_uniswapRouter, _uniswapFactory);
        __Audit_init(_salt, _nftAddress);
    }

    function addLiquidity(
        address tokenA, 
        uint256 tokenAAmount, 
        address tokenB, 
        uint256 tokenBAmount
    ) external payable onlyOwner {        
        _addLiquidityToPool(tokenA, tokenB, tokenAAmount, tokenBAmount);        
    }
}
