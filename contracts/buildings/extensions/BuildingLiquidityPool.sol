// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {SafeHTS} from "../../common/safe-HTS/SafeHTS.sol";
import {HederaTokenService} from "../../common/hedera/HederaTokenService.sol";
import {IUniswapV2Factory, IUniswapV2Pair, IUniswapV2Router02} from "../interface/UniswapInterface.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract BuildingLiquidityPool is Initializable {
    address public uniswapRouter;
    address public uniswapFactory;

    function __Liquidity_init (address _uniswapRouter, address _uniswapFactory) internal onlyInitializing {
        uniswapRouter = _uniswapRouter;
        uniswapFactory = _uniswapFactory;
    }

    function _addLiquidityToPool(
        address _tokenA, 
        address _tokenB, 
        uint256 _tokenAAmount, 
        uint256 _tokenBAmount
    ) internal returns(uint amountA, uint amountB, uint liquidity) {
        address pair = IUniswapV2Factory(uniswapFactory).getPair(_tokenA, _tokenB);
        
        if (pair == address(0)){
            pair = IUniswapV2Factory(uniswapFactory).createPair(_tokenA, _tokenB);
        }

        _approveToken(_tokenA, _tokenAAmount, address(uniswapRouter));
        _approveToken(_tokenB, _tokenBAmount, address(uniswapRouter));
        
        (
            amountA, // The actual amounts of tokenA that were added to the pool.
            amountB, // The actual amounts of tokenB that were added to the pool.
            liquidity // The number of liquidity tokens (LP tokens) minted and sent to the to address.
        ) = IUniswapV2Router02(uniswapRouter).addLiquidity(
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

    function _approveToken(address _token, uint256 _tokenAmount, address _spender) internal {
        if (SafeHTS.safeIsToken(_token)) {
            SafeHTS.safeApprove(_token, _spender, _tokenAmount);
        } else {
            IERC20(_token).approve(_spender, _tokenAmount);
        }
    }
}
