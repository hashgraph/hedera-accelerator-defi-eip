//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC20} from "./ERC20.sol";
import {IERC4626} from "./IERC4626.sol";

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {PythUtils} from "@pythnetwork/pyth-sdk-solidity/PythUtils.sol";

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {ITokenBalancer} from "./interfaces/ITokenBalancer.sol";
import {IAutoCompounder} from "./interfaces/IAutoCompounder.sol";

/**
 * @title Slice
 *
 * The contract that helps to maintain A/V (Vault Share/AutoCompaunder) token balances.
 */
contract Slice is ITokenBalancer, Ownable {
    using SafeERC20 for IERC20;
    using PythUtils for int64;
    using Bits for uint256;

    // Max tokens amount to rebalance
    uint8 constant MAX_TOKENS_AMOUNT = 10;

    // Uniswap V2 Router
    IUniswapV2Router02 public uniswapV2Router;

    // Oracle
    IPyth public pyth;

    // USDC address
    address public usdc;

    // Token address => Token info
    mapping(address token => TokenInfo) public tokenInfo;

    // A/V token addresses
    address[] public tokens;

    // Underlying tokens refer to A/V tokens
    address[] public underlyingTokens;

    // Token balances
    mapping(address token => uint256 balance) public balances;

    struct TradeAmount {
        address token;
        uint256 amountToTrade;
    }

    struct TokenValuePayload {
        address token;
        uint256 value;
        uint256 balance;
        uint256 price;
        uint256 targetPercentage;
    }

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param _pyth The address of the Pyth oracle.
     * @param _uniswapV2Router The address of the Uniswap Router contract.
     * @param _usdc The address of the USDC token.
     */
    constructor(address _pyth, address _uniswapV2Router, address _usdc) Ownable(msg.sender) {
        require(_pyth != address(0), "TokenBalancer: Invalid Pyth address");
        require(_uniswapV2Router != address(0), "TokenBalancer: Invalid Uniswap Router address");
        require(_usdc != address(0), "TokenBalancer: Invalid USDC token address");

        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        pyth = IPyth(_pyth);
        usdc = _usdc;
    }

    /**
     * @dev Calculates token value in USD.
     *
     * @param _aToken The A/V token address.
     */
    function getTokenValueInUSDC(address _aToken) public view returns (TokenValuePayload memory) {
        TokenInfo storage aTokenInfo = tokenInfo[_aToken];

        require(aTokenInfo.aToken != address(0), "TokenBalancer: The token doesn't exist");

        if (aTokenInfo.isAutoCompounder) {
            uint256 aTokenBalance = IERC20(_aToken).balanceOf(address(this));
            uint256 exchangeRate = IAutoCompounder(_aToken).exchangeRate();
            uint256 usdPrice = _getPrice(aTokenInfo.token, aTokenInfo.priceId);

            uint256 currentValue = (aTokenBalance * exchangeRate * usdPrice) / 1e18;

            return TokenValuePayload(_aToken, currentValue, aTokenBalance, usdPrice, aTokenInfo.targetPercentage);
        } else {
            uint256 vTokenBalance = IERC20(_aToken).balanceOf(address(this));
            uint256 usdPrice = _getPrice(aTokenInfo.token, aTokenInfo.priceId);

            return
                TokenValuePayload(
                    _aToken,
                    vTokenBalance * usdPrice,
                    vTokenBalance,
                    usdPrice,
                    aTokenInfo.targetPercentage
                );
        }
    }

    /**
     * @dev Calculates target amount needed to add to each token.
     */
    function _calculateAmountsToTrade() public view returns (TradeAmount[] memory amounts, uint256 totalValue) {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; i++) {
            TokenValuePayload memory valuePayload = getTokenValueInUSDC(tokens[i]); // get current value of each A/V token

            totalValue += valuePayload.value; // calculate total value on the contract

            uint256 targetValue = (totalValue * valuePayload.targetPercentage) / 10000; // calculate target value for each A/V token
            uint256 targetQuantity = targetValue / valuePayload.price; // calculate target quantity to add to reach target value

            amounts[i] = TradeAmount(valuePayload.token, targetQuantity - valuePayload.balance); // return amount to swap for each A/V token
        }
    }

    /**
     * @dev Makes a set of swaps to reach the target allocation of each token.
     */
    function rebalance() public {
        (TradeAmount[] memory amounts, uint256 totalValue) = _calculateAmountsToTrade();

        for (uint256 i = 0; i < amounts.length; i++) {
            TokenInfo storage aTokenInfo = tokenInfo[amounts[i].token];

            // withdraw calculated amounts of the underlying tokens and burn A/V tokens equivalent
            if (aTokenInfo.isAutoCompounder) {
                IAutoCompounder(amounts[i].token).withdraw(amounts[i].amountToTrade);
            } else {
                IERC4626(amounts[i].token).withdraw(amounts[i].amountToTrade, address(this), address(this));
            }

            // Decrease A/V token balance by withdrawn amount
            balances[amounts[i].token] -= amounts[i].amountToTrade;
        }

        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            _swapTokensForTokens(balances[underlyingTokens[i]], underlyingTokens[i], usdc); // Swap whole underlying tokens balance for USDC

            _swapTokensForTokens(balances[address(usdc)], usdc, underlyingTokens[i]); // Swap USDC for underlying tokens
        }
    }

    /**
     * @dev Performs the swap of Token to Token using Uniswap Router.
     *
     * @param amount The A token amount to swap.
     * @param tokenA The A token address.
     * @param tokenB The B token address.
     * @return The swap amount.
     */
    function _swapTokensForTokens(uint256 amount, address tokenA, address tokenB) internal returns (uint256) {
        address[] memory path = new address[](2);
        (path[0], path[1]) = (tokenA, tokenB);

        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(
            amount,
            0, // accept any amount of output token
            path,
            address(this),
            block.timestamp
        );
        return amounts[1];
    }

    /**
     * @dev Deposit underlying token to external Vault/AutoCompaunder.
     *
     * @param token The token address.
     * @param amount The amount to deposit.
     */
    function deposit(address token, uint256 amount) external {
        require(tokenInfo[token].priceId.length != 0, "TokenBalancer: Invalid token to deposit");
        require(amount != 0, "TokenBalancer: Invalid amount");

        balances[token] += amount;

        IERC4626(token).deposit(amount, msg.sender);

        emit Deposit(token, msg.sender, amount);
    }

    /**
     * @dev Gets token price and calculate one dollar in any token.
     *
     * @param token The token address.
     * @param priceId The price ID in terms of Pyth oracle.
     */
    function _getPrice(address token, bytes32 priceId) public view returns (uint256 oneDollarInToken) {
        PythStructs.Price memory price = pyth.getPrice(priceId);
        return price.price.convertToUint(price.expo, IERC20Metadata(token).decimals());
    }

    /**
     * @dev Updates oracle price.
     *
     * @param pythPriceUpdate The pyth price update.
     */
    function update(bytes[] calldata pythPriceUpdate) public payable {
        uint updateFee = pyth.getUpdateFee(pythPriceUpdate);
        pyth.updatePriceFeeds{value: updateFee}(pythPriceUpdate);
    }

    /**
     * @dev Adds A/V token to the balancer system.
     *
     * @param aToken The A/V token address.
     * @param priceId The underlying token oracle price ID.
     * @param percentage The allocation percentage.
     * @param isAutoCompounder The bool flag true if the token is AutoCompounder.
     */
    function addTrackingToken(address aToken, bytes32 priceId, uint256 percentage, bool isAutoCompounder) public {
        require(aToken != address(0), "TokenBalancer: Invalid token address");
        require(priceId.length != 0, "TokenBalancer: Invalid price ID");
        require(percentage < 10000 && percentage > 0, "TokenBalancer: Invalid allocation percentage");
        require(tokenInfo[aToken].priceId == 0, "TokenBalancer: Token already exists");
        require(tokens.length <= MAX_TOKENS_AMOUNT, "TokenBalancer: Max amount of tokens reached");

        address underlying = IERC4626(aToken).asset();

        tokenInfo[aToken] = TokenInfo(aToken, underlying, priceId, percentage, isAutoCompounder);

        tokens.push(aToken);

        emit TokenAdded(aToken, priceId, percentage);
    }

    /**
     * @dev Sets a target percentage for a reward token.
     *
     * @param token The token address.
     * @param percentage The allocation percentage.
     */
    function setAllocationPercentage(address token, uint256 percentage) external {
        require(percentage < 10000 && percentage != 0, "TokenBalancer: Invalid percentage");
        require(tokenInfo[token].targetPercentage != 0, "TokenBalancer: Token doesn't exist");

        tokenInfo[token].targetPercentage = percentage;

        emit TargetAllocationPercentageChanged(token, percentage);
    }
}

library Bits {
    uint256 internal constant ONE = uint256(1);

    /**
     * @dev Sets the bit at the given 'index' in 'self' to '1'.
     *
     * @return Returns the modified value.
     */
    function setBit(uint256 self, uint8 index) internal pure returns (uint256) {
        return self | (ONE << index);
    }
}
