// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {BuildingBase} from './BuildingBase.sol';
import {BuildingLiquidityPool} from "./extensions/BuildingLiquidityPool.sol";
import {BuildingAudit} from "./extensions/BuildingAudit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Building is BuildingBase, BuildingLiquidityPool, BuildingAudit {

    function initialize (
        bytes32 _salt,
        address _uniswapRouter, 
        address _uniswapFactory,
        address _nftAddress
    ) public virtual payable initializer {
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
    ) public virtual payable returns (uint amountA, uint amountB, uint liquidity, address pair) {        
        IERC20(tokenA).transferFrom(_msgSender(), address(this), tokenAAmount);
        IERC20(tokenB).transferFrom(_msgSender(), address(this), tokenBAmount);
        (amountA, amountB, liquidity, pair) =
            _addLiquidityToPool(tokenA, tokenB, tokenAAmount, tokenBAmount);        
    }
}
