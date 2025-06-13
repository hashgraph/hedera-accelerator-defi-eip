// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Building} from '../Building.sol';

contract BuildingMock is Building {
    uint public amountA;
    uint public amountB;
    uint public liquidity;
    address public pair;

    function version() public pure returns (string memory) {
        return '2.0';
    }

    function initialize (
        address _uniswapRouter, 
        address _uniswapFactory,
        address _nftAddress
    ) public override {
       super.initialize(_uniswapRouter, _uniswapFactory, _nftAddress);
    }

    function addLiquidity(
        address tokenA, 
        uint256 tokenAAmount, 
        address tokenB, 
        uint256 tokenBAmount
    ) public  override onlyOwner returns (uint, uint, uint,address) {        
        (amountA, amountB, liquidity, pair)=
        super.addLiquidity(
            tokenA, 
            tokenAAmount, 
            tokenB, 
            tokenBAmount
        );

        return (amountA, amountB, liquidity, pair);
    }
}
