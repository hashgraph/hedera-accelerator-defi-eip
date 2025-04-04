//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC7540} from "../erc7540/interfaces/IERC7540.sol";

import {IAutoCompounder} from "./interfaces/IAutoCompounder.sol";
import {ISlice} from "./interfaces/ISlice.sol";
import {IRewards} from "./interfaces/IRewards.sol";

/**
 * @title Slice
 *
 * The contract represents a derivatives fund on tokenized assets, in current case buildings.
 * The main contract responsibility is to rebalance the asset portfolio (utilising USD prices)
 * and maintain predefined allocation of the stored assets.
 */
contract Slice is ISlice, ERC20, Ownable, ERC165 {
    using SafeERC20 for IERC20;

    // Basis points for calculations with percentages
    uint16 private constant BASIS_POINTS = 10000;

    // Max tokens amount to store
    uint8 private constant MAX_TOKENS_AMOUNT = 10;

    // Slice group
    string private _metadataUri;

    // Allocations array for each aToken stored
    Allocation[] private _allocations;

    // Uniswap router V2
    IUniswapV2Router02 private _uniswapRouter;

    // USDC
    address private _baseToken;

    // Price oracle
    mapping(address => AggregatorV3Interface) private _priceFeeds;

    // Token balances
    mapping(address => uint256) private _balances;

    // Rebalance payload struct (used for caching calculation data)
    struct RebalancePayload {
        address aToken; // aToken address
        address asset; // Underlying asset
        uint256 targetUnderlyingAmount; // Target amount in terms of underlying
        uint256 aTokenTargetAmount; // aToken target amount
        uint256 currentBalance; // Current aToken balance
        uint256 availableReward; // Available vault reward
    }

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param uniswapRouter_ The address of the Uniswap router.
     * @param baseToken_ The address of the base token.
     * @param name_ The name of the sToken.
     * @param symbol_ The symbol of the sToken.
     * @param metadataUri_ The Slice metadata URI.
     */
    constructor(
        address uniswapRouter_,
        address baseToken_,
        string memory name_,
        string memory symbol_,
        string memory metadataUri_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(uniswapRouter_ != address(0), "Slice: Invalid Uniswap router address");
        require(baseToken_ != address(0), "Slice: Invalid USDC token address");
        require(bytes(metadataUri_).length != 0, "Slice: Invalid metadata URI");

        _uniswapRouter = IUniswapV2Router02(uniswapRouter_);
        _baseToken = baseToken_;
        _metadataUri = metadataUri_;
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deposits to the AutoCompounder contract.
     * @inheritdoc ISlice
     */
    function deposit(address aToken, uint256 amount) external returns (uint256 aTokenAmount) {
        require(amount > 0, "Slice: Invalid amount");

        address _asset = getTokenAllocation(aToken).asset;

        require(_asset != address(0), "Slice: Allocation for the token doesn't exist");

        address _sender = msg.sender;

        // Transfer underlying token from user to contract
        IERC20(_asset).safeTransferFrom(_sender, address(this), amount);

        // Deposit to AutoCompounder
        IERC20(_asset).approve(aToken, amount);
        aTokenAmount = IAutoCompounder(aToken).deposit(amount, address(this));

        _balances[aToken] += aTokenAmount;

        // Mint appropriate sToken amount to sender
        _mint(_sender, aTokenAmount);

        emit Deposit(aToken, _sender, amount);
    }

    /**
     * @dev Withdraws set of stored tokens.
     * @inheritdoc ISlice
     */
    function withdraw(uint256 sTokenAmount) external returns (uint256[] memory amounts) {
        require(sTokenAmount > 0, "Slice: Invalid amount");

        address _sender = msg.sender;

        // Burn sToken
        _burn(_sender, sTokenAmount);

        amounts = new uint256[](_allocations.length);

        address currentAToken;
        uint256 currentBalance;

        // Calculate proportional assets to return
        uint256 userShare = (sTokenAmount * decimals()) / totalSupply();
        for (uint256 i = 0; i < _allocations.length; i++) {
            currentAToken = _allocations[i].aToken;
            currentBalance = _balances[currentAToken];

            amounts[i] = (currentBalance * userShare) / decimals();
            IERC20(currentAToken).safeTransfer(_sender, amounts[i]);

            emit Withdraw(currentAToken, _sender, amounts[i]);
        }
    }

    /*///////////////////////////////////////////////////////////////
                        ALLOCATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Adds new aToken allocation.
     * @inheritdoc ISlice
     */
    function addAllocation(address aToken, address priceFeed, uint16 percentage) external {
        require(aToken != address(0), "Slice: Invalid aToken address");
        require(priceFeed != address(0), "Slice: Invalid price feed address");
        require(percentage != 0 && percentage != BASIS_POINTS, "Slice: Invalid allocation percentage");
        require(getTokenAllocation(aToken).aToken == address(0), "Slice: Allocation for the passed token exists");
        require(_allocations.length < MAX_TOKENS_AMOUNT, "Slice: Allocation limit exceeds");
        require(
            ERC165Checker.supportsInterface(aToken, type(IAutoCompounder).interfaceId),
            "Slice: Unsupported interface ID"
        );

        // Get underlying asset from Autocompounder
        address asset = IAutoCompounder(aToken).asset();

        _allocations.push(Allocation({aToken: aToken, asset: asset, targetPercentage: percentage}));
        _priceFeeds[asset] = AggregatorV3Interface(priceFeed);

        emit AllocationAdded(aToken, asset, priceFeed, percentage);
    }

    /**
     * @dev Sets new aToken allocation percentage.
     * @inheritdoc ISlice
     */
    function setAllocationPercentage(address aToken, uint16 newPercentage) external {
        require(aToken != address(0), "Slice: Invalid aToken address");
        require(newPercentage != 0 && newPercentage != BASIS_POINTS, "Slice: Invalid percentage");
        require(
            getTokenAllocation(aToken).aToken != address(0),
            "Slice: Allocation for the passed token doesn't exist"
        );

        for (uint256 i = 0; i < _allocations.length; i++) {
            if (_allocations[i].aToken == aToken) {
                _allocations[i].targetPercentage = newPercentage;
            }
        }

        emit AllocationPercentageChanged(aToken, newPercentage);
    }

    /*///////////////////////////////////////////////////////////////
                        REBALANCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Handles withdraw from IERC4626 and IERC7540 assuming current unlocked amount of shares.
     *
     * @param aToken The address of aToken.
     * @param amountToWithdraw The needed aToken amount to withdraw.
     * @param exchangeRate The vToken/aToken exchange rate to convert and compare with unlocked underlying amount.
     * @return withdrawnAmount The withdrawn amount of underlying token.
     */
    function _handleWithdraw(
        address aToken,
        uint256 amountToWithdraw,
        uint256 exchangeRate
    ) public returns (uint256 withdrawnAmount) {
        address _vault = IAutoCompounder(aToken).vault();
        uint256 maxWithdrawAmount = IERC4626(_vault).maxWithdraw(aToken);

        uint256 neededUnderlying = amountToWithdraw / exchangeRate; // Convert aToken to underlying for checks

        if (maxWithdrawAmount == 0) return 0; // Return 0 if tokens are locked

        if (ERC165Checker.supportsInterface(_vault, type(IERC7540).interfaceId)) {
            IERC7540(_vault).requestRedeem(neededUnderlying, aToken, aToken); // Request full needed amount to meet ideal balance in next iteration

            if (maxWithdrawAmount < neededUnderlying) {
                return IAutoCompounder(aToken).withdraw(maxWithdrawAmount * exchangeRate, address(this)); // Withdraw max possible amount
            } else {
                return IAutoCompounder(aToken).withdraw(amountToWithdraw, address(this)); // Withdraw needed amount
            }
        } else {
            if (maxWithdrawAmount < neededUnderlying) {
                return IAutoCompounder(aToken).withdraw(maxWithdrawAmount * exchangeRate, address(this)); // Withdraw max possible amount
            } else {
                return IAutoCompounder(aToken).withdraw(amountToWithdraw, address(this)); // Withdraw needed amount
            }
        }
    }

    /**
     * @dev Generates array of payloads with caching target amounts and balances for each aToken.
     *
     * @return payloads The array of rebalance payloads.
     */
    function _generateRebalancePayload() internal returns (RebalancePayload[] memory payloads) {
        uint256 totalValue = _getTotalValue();

        address aToken;
        address asset;
        uint256 targetValue;
        uint256 targetUnderlyingAmount;
        uint256 aTokenTargetAmount;
        uint256 aTokenExcessAmount;
        uint256 withdrawnUnderlyingAmount;
        uint256 aTokenBalance;

        payloads = new RebalancePayload[](_allocations.length);

        for (uint256 i = 0; i < _allocations.length; i++) {
            aToken = _allocations[i].aToken;
            asset = _allocations[i].asset;

            (, , uint256 underlyingPrice, uint256 aTokenToUnderlyingRate) = _getTokenValue(aToken, asset);

            // Target amount in underlying
            targetValue = (totalValue * _allocations[i].targetPercentage) / BASIS_POINTS; // Target value in USD
            targetUnderlyingAmount = (targetValue * (10 ** IERC20Metadata(asset).decimals())) / underlyingPrice; // Target amount in underlying

            // Target amount in aToken
            aTokenTargetAmount = targetUnderlyingAmount * aTokenToUnderlyingRate;

            aTokenBalance = _balances[aToken];

            if (aTokenBalance > aTokenTargetAmount) {
                aTokenExcessAmount = aTokenBalance - aTokenTargetAmount;

                withdrawnUnderlyingAmount = _handleWithdraw(aToken, aTokenExcessAmount, aTokenToUnderlyingRate);

                if (withdrawnUnderlyingAmount != 0) {
                    // Swap excess underlying to USDC for next 'buy' trades
                    _tradeForToken(asset, baseToken(), withdrawnUnderlyingAmount);

                    _balances[baseToken()] = IERC20(baseToken()).balanceOf(address(this));

                    payloads[i] = RebalancePayload({
                        aToken: aToken,
                        asset: asset,
                        targetUnderlyingAmount: targetUnderlyingAmount,
                        aTokenTargetAmount: aTokenTargetAmount,
                        currentBalance: aTokenBalance - aTokenExcessAmount,
                        availableReward: 0
                    });
                } else {
                    payloads[i] = RebalancePayload({
                        aToken: aToken,
                        asset: asset,
                        targetUnderlyingAmount: targetUnderlyingAmount,
                        aTokenTargetAmount: aTokenTargetAmount,
                        currentBalance: aTokenBalance,
                        availableReward: IRewards(IAutoCompounder(aToken).vault()).getUserReward(aToken, baseToken())
                    });
                }
            } else {
                payloads[i] = RebalancePayload({
                    aToken: aToken,
                    asset: asset,
                    targetUnderlyingAmount: targetUnderlyingAmount,
                    aTokenTargetAmount: aTokenTargetAmount,
                    currentBalance: aTokenBalance,
                    availableReward: IRewards(IAutoCompounder(aToken).vault()).getUserReward(aToken, baseToken())
                });
            }
        }
    }

    /**
     * @dev Makes set of swaps to reach target balances of aTokens from generated payloads.
     */
    function rebalance() external {
        RebalancePayload[] memory payloads = _generateRebalancePayload();

        address aToken;
        address asset;
        uint256 aTokenTargetAmount;
        uint256 balance;
        uint256 availableReward;
        uint256 difference;
        uint256 currentExchangeRate;
        uint256 neededUnderlying;
        uint256 withdrawnUnderlyingAmount;
        uint256 neededUsdcToSwapForUnderlying;
        uint256 baseTokenBalance;
        uint256 underlyingBalance;

        for (uint256 i = 0; i < payloads.length; i++) {
            aToken = payloads[i].aToken;
            asset = payloads[i].asset;
            aTokenTargetAmount = payloads[i].aTokenTargetAmount;
            balance = payloads[i].currentBalance;
            availableReward = payloads[i].availableReward;

            // Skip the iteration if already have 'ideal' balance or tokens are locked
            // Balance can't be gt 'aTokenTargetAmount' amount cuz possible excess was swapped in previous step, if tokens were unlocked
            if (balance >= aTokenTargetAmount) continue;

            currentExchangeRate = IAutoCompounder(aToken).exchangeRate();

            difference = aTokenTargetAmount - balance;
            neededUnderlying = difference / currentExchangeRate;

            if (availableReward > 0) {
                difference > balance
                    ? withdrawnUnderlyingAmount = _handleWithdraw(aToken, balance, currentExchangeRate)
                    : withdrawnUnderlyingAmount = _handleWithdraw(aToken, difference, currentExchangeRate);
            }

            if (withdrawnUnderlyingAmount == 0) continue; // Skip the interation due to locked tokens

            // Swap underlying for USDC
            _tradeForToken(asset, baseToken(), withdrawnUnderlyingAmount);

            neededUsdcToSwapForUnderlying = _getQuoteAmount(
                neededUnderlying + withdrawnUnderlyingAmount,
                baseToken(),
                asset
            );

            baseTokenBalance = IERC20(baseToken()).balanceOf(address(this));

            if (baseTokenBalance < neededUsdcToSwapForUnderlying) {
                // Swap whole USDC balance for underlying
                _tradeForToken(_baseToken, asset, baseTokenBalance);
            } else {
                // Swap USDC for aToken equivalent in underlying token
                _tradeForToken(_baseToken, asset, neededUsdcToSwapForUnderlying);
            }

            underlyingBalance = IERC20(asset).balanceOf(address(this));

            // Reinvest to get aToken
            IERC20(asset).approve(aToken, underlyingBalance);
            _balances[aToken] += IAutoCompounder(aToken).deposit(underlyingBalance, address(this));
        }
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns total portfolio value in USD.
     */
    function _getTotalValue() internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < _allocations.length; i++) {
            (uint256 currentValue, , , ) = _getTokenValue(_allocations[i].aToken, _allocations[i].asset);
            totalValue += currentValue;
        }
    }

    /**
     * @dev Gets the USD value of a token held in the contract.
     *
     * @param aToken The aToken address.
     * @param asset The underlying asset address.
     */
    function _getTokenValue(
        address aToken,
        address asset
    )
        internal
        view
        returns (uint256 currentValue, uint256 underlyingValue, uint256 underlyingPrice, uint256 aTokenToUnderlyingRate)
    {
        uint256 balance = _balances[aToken];
        aTokenToUnderlyingRate = IAutoCompounder(aToken).exchangeRate();
        underlyingPrice = uint256(getChainlinkDataFeedLatestAnswer(asset));

        // Get Underlying value in aToken
        underlyingValue = balance * aTokenToUnderlyingRate;

        // Get underlying value in USD
        currentValue = (underlyingValue * underlyingPrice) / (10 ** IERC20Metadata(aToken).decimals());
    }

    /**
     * @dev Trades USDC or other tokens to buy the desired token.
     *
     * @param token The address of token to swap.
     * @param targetToken The address of token to receive.
     * @param amountIn The input amount.
     */
    function _tradeForToken(address token, address targetToken, uint256 amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = targetToken;

        IERC20(path[0]).approve(uniswapV2Router(), amountIn);

        _uniswapRouter.swapExactTokensForTokens(
            amountIn,
            0, // Minimum output (slippage tolerance could be added here)
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Returns the amount of input token needed to swap in order to get amount out of output token.
     *
     * @param amountOut The desired amount out of output token.
     * @param tokenIn The input token address.
     * @param tokenOut The output token address.
     */
    function _getQuoteAmount(uint256 amountOut, address tokenIn, address tokenOut) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amountsIn = _uniswapRouter.getAmountsIn(amountOut, path);
        return amountsIn[0];
    }

    /*///////////////////////////////////////////////////////////////
                         PRICE HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the latest price data from the Chainlink feed
     * @return The latest answer from the Chainlink data feed
     */
    function getChainlinkDataFeedLatestAnswer(address token) public view returns (int) {
        (
            ,
            /* uint80 roundID */ int answer /* uint startedAt */ /* uint timeStamp */ /* uint80 answeredInRound */,
            ,
            ,

        ) = _priceFeeds[token].latestRoundData();
        return answer;
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns token allocation for the passed aToken address.
     * @inheritdoc ISlice
     */
    function getTokenAllocation(address aToken) public view returns (Allocation memory) {
        for (uint256 i = 0; i < _allocations.length; i++) {
            if (_allocations[i].aToken == aToken) return _allocations[i];
        }
    }

    /**
     * @dev Returns all token allocations.
     */
    function allocations() external view returns (Allocation[] memory) {
        return _allocations;
    }

    /**
     * @dev Returns the price oracle address for provided token.
     */
    function priceFeed(address token) public view returns (address) {
        return address(_priceFeeds[token]);
    }

    /**
     * @dev Returns the Uniswap V2 router address.
     */
    function uniswapV2Router() public view returns (address) {
        return address(_uniswapRouter);
    }

    /**
     * @dev Returns the base token used for trading (e.g., USDC).
     */
    function baseToken() public view returns (address) {
        return _baseToken;
    }

    /**
     * @dev Returns the Slice metadata URI.
     */
    function metadataUri() external view returns (string memory) {
        return _metadataUri;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ISlice).interfaceId || super.supportsInterface(interfaceId);
    }
}
