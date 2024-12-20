// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

struct Price {
    uint256 price;
    uint256 interval;
}

struct PriceThreshold {
    uint256 maxSellAmount;
    uint256 maxBuyAmount;
    uint256 interval;
}

/**
 * @title One Sided Exchange
 *
 * The contract which represents a one sided exchange
 at desired prices.
 */
contract OneSidedExchange is ReentrancyGuard, Ownable {
    event Deposit(address token, uint256 amount);
    event Withdraw(address token, uint256 amount);
    event SwapSuccess(
        address indexed trader,
        address tokenA,
        address tokenB,
        uint256 tokenAAmount,
        uint256 tokenBAmount
    );
    error InvalidAmount(string message);
    error NoPriceExists(string message);

    mapping(address => Price) internal _buyPrices;
    mapping(address => Price) internal _sellPrices;
    mapping(address => PriceThreshold) internal _thresholds;
    mapping(address => uint256) internal _buyAmounts;
    mapping(address => uint256) internal _sellAmounts;

    constructor() Ownable(msg.sender) {}

    function withdraw(address token, uint256 amount) public nonReentrant onlyOwner {
        if (amount <= 0) {
            revert InvalidAmount("Invalid amount");
        }

        if (ERC20(token).balanceOf(address(this)) < amount) {
            revert InvalidAmount("Not enought tokens balance to withdraw");
        }

        _withdraw(token, amount);
    }

    function deposit(address token, uint256 amount) public nonReentrant onlyOwner {
        if (amount <= 0) {
            revert InvalidAmount("Invalid amount");
        }

        _deposit(msg.sender, token, amount);
    }

    function swap(address tokenA, address tokenB, uint256 amount) public nonReentrant {
        _swap(msg.sender, tokenA, tokenB, amount);
    }

    function _deposit(address signer, address token, uint256 amount) internal {
        // owner should give allowance for a contract to transfer n tokens amount.
        uint256 _amount = amount * (10 ** getDecimals(token));
        ERC20(token).transferFrom(signer, address(this), _amount);

        emit Deposit(token, amount);
    }

    function _withdraw(address token, uint256 amount) internal {
        uint256 _amount = amount * (10 ** getDecimals(token));
        ERC20(token).transfer(this.owner(), _amount);

        emit Withdraw(token, amount);
    }

    function _swap(address trader, address tokenA, address tokenB, uint256 amount) internal {
        (uint256 tokenAAmount, uint256 tokenBAmount) = _checkIfExchangeAllowedForPair(tokenA, tokenB, amount, trader);

        // trader should give allowance for a contract to transfer n tokens amount.
        ERC20(tokenA).transferFrom(trader, address(this), tokenAAmount);
        ERC20(tokenB).transfer(trader, tokenBAmount);

        _sellAmounts[tokenA] += tokenAAmount;
        _buyAmounts[tokenB] += tokenBAmount;

        emit SwapSuccess(trader, tokenA, tokenB, tokenAAmount, tokenBAmount);
    }

    function _checkIfExchangeAllowedForPair(
        address tokenA,
        address tokenB,
        uint256 amount,
        address trader
    ) internal view returns (uint256 tokenAAmount, uint256 tokenBAmount) {
        PriceThreshold memory tokenAThreshold = _thresholds[tokenA];
        PriceThreshold memory tokenBThreshold = _thresholds[tokenB];

        (uint256 tokenASellAmount, uint256 tokenBBuyAmount) = estimateTokenReturns(tokenA, tokenB, amount);
        uint256 balanceOfAToken = ERC20(tokenA).balanceOf(trader) * (10 ** getDecimals(tokenA));
        uint256 balanceOfBToken = ERC20(tokenB).balanceOf(address(this)) * (10 ** getDecimals(tokenB));

        if (tokenASellAmount > balanceOfAToken) {
            revert InvalidAmount("No enough tokens to sell");
        } else if (tokenBBuyAmount > balanceOfBToken) {
            revert InvalidAmount("No enough tokens to buy");
        }

        if (tokenAThreshold.maxSellAmount != 0 && tokenAThreshold.interval < block.timestamp) {
            if ((_sellAmounts[tokenA] + tokenASellAmount) > tokenAThreshold.maxSellAmount) {
                revert InvalidAmount("Max sell amount of tokens exceeded");
            }
        }

        if (tokenBThreshold.maxBuyAmount != 0 && tokenBThreshold.interval < block.timestamp) {
            if ((_buyAmounts[tokenB] + tokenBBuyAmount) > tokenBThreshold.maxBuyAmount) {
                revert InvalidAmount("Max buy amount of tokens exceeded");
            }
        }

        return (tokenASellAmount, tokenBBuyAmount);
    }

    function estimateTokenReturns(
        address tokenA,
        address tokenB,
        uint256 amount
    ) public view returns (uint256 tokenASellAmount, uint256 tokenBBuyAmount) {
        if (_buyPrices[tokenB].interval == 0 || _sellPrices[tokenA].interval == 0) {
            revert NoPriceExists("Sell or buy price for pair not found");
        } else if (_buyPrices[tokenB].interval > block.timestamp || _sellPrices[tokenA].interval > block.timestamp) {
            revert NoPriceExists("Sell or buy price for pair is not valid");
        }

        uint256 tokenADecimals = 10 ** getDecimals(tokenA);
        uint256 tokenBDecimals = 10 ** getDecimals(tokenB);

        if (tokenADecimals != tokenBDecimals) {
            uint256 tokenASellAmount = amount * _sellPrices[tokenA].price;
            uint256 tokenBBuyAmount = ((tokenASellAmount * _sellPrices[tokenA].price) / _buyPrices[tokenB].price);

            return (tokenASellAmount * tokenADecimals, tokenBBuyAmount * tokenBDecimals);
        } else {
            uint256 tokenASellAmount = (amount * tokenADecimals) * _sellPrices[tokenA].price;
            uint256 tokenBBuyAmount = ((tokenASellAmount * _sellPrices[tokenA].price) / _buyPrices[tokenB].price);

            return (tokenASellAmount, tokenBBuyAmount);
        }
    }

    function getDecimals(address token) internal view returns (uint8) {
        return ERC20(token).decimals();
    }

    function setThreshold(
        address token,
        uint256 maxSellAmount,
        uint256 maxBuyAmount,
        uint256 interval
    ) public onlyOwner {
        uint256 _decimals = getDecimals(token);

        _thresholds[token] = PriceThreshold(
            maxSellAmount * (10 ** _decimals),
            maxBuyAmount * (10 ** _decimals),
            interval
        );
    }

    function setBuyPrice(address token, uint256 amount, uint256 interval) public onlyOwner {
        _buyPrices[token] = Price(amount, interval);
    }

    function setSellPrice(address token, uint256 amount, uint256 interval) public onlyOwner {
        _sellPrices[token] = Price(amount, interval);
    }
}
