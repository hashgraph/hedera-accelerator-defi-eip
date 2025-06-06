// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {FixedPointMathLib} from "../math/FixedPointMathLib.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC7540} from "../erc7540/interfaces/IERC7540.sol";

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IUniswapV2Router02} from "../uniswap/interfaces/IUniswapV2Router02.sol";

import {IAutoCompounder} from "./interfaces/IAutoCompounder.sol";
import {IRewards} from "../erc4626/interfaces/IRewards.sol";

/**
 * @title AutoCompounder
 * @author Hashgraph
 *
 * The contract represents a simple AutoCompounder, that allows to reinvest vault rewards.
 */
contract AutoCompounder is IAutoCompounder, ERC20, Ownable, ERC165 {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    // Precision factor
    uint256 private constant PRECISION = 1e18;

    // Min reward to perform claim & reinvest
    uint256 internal constant MIN_REWARD = 10e6; // 10$

    // Vault
    IERC4626 private immutable _vault;

    // Cached vault type IERC4626/IERC7540
    bool private immutable isAsync;

    // Underlying token
    address private immutable _underlying;

    // Uniswap V2 Router
    IUniswapV2Router02 private _uniswapV2Router;

    // USDC token
    address private _usdc;

    // Uniswap swap path to convert from USDC to underlying asset
    address[] internal _path;

    // User => claimed amount
    mapping(address => uint256) internal _userClaimedRewards;

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param uniswapV2Router_ The address of the Uniswap Router contract.
     * @param vault_ The Vault contract address.
     * @param usdc_ The address of the USDC token.
     * @param name_ The aToken name.
     * @param symbol_ The aToken symbol.
     * @param operator_ The operator address used in case of Async Vault, e.g. Slice.
     */
    constructor(
        address uniswapV2Router_,
        address vault_,
        address usdc_,
        string memory name_,
        string memory symbol_,
        address operator_
    ) payable ERC20(name_, symbol_) Ownable(msg.sender) {
        require(uniswapV2Router_ != address(0), "AutoCompounder: Invalid Uniswap Router address");
        require(vault_ != address(0), "AutoCompounder: Invalid Vault address");
        require(usdc_ != address(0), "AutoCompounder: Invalid USDC token address");

        isAsync = ERC165Checker.supportsInterface(vault_, type(IERC7540).interfaceId);
        require(
            isAsync || ERC165Checker.supportsInterface(vault_, type(IERC4626).interfaceId),
            "AutoCompounder: Unsupported vault interface ID"
        );

        _uniswapV2Router = IUniswapV2Router02(uniswapV2Router_);
        _underlying = IERC4626(vault_).asset();
        _vault = IERC4626(vault_);
        _usdc = usdc_;

        _path = new address[](2);
        (_path[0], _path[1]) = (usdc(), asset());

        if (isAsync) {
            IERC7540(vault()).setOperator(operator_, true);
        }
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deposits staking token to the Vault and returns shares.
     * @inheritdoc IAutoCompounder
     */
    function deposit(uint256 assets, address receiver) external override returns (uint256 amountToMint) {
        require(assets != 0, "AutoCompounder: Invalid assets amount");
        require(receiver != address(0), "AutoCompounder: Invalid receiver address");

        address sender = _msgSender();

        // Calculate aToken amount to mint using exchange rate
        amountToMint = assets.mulDivDown(PRECISION, exchangeRate());

        IERC20(asset()).safeTransferFrom(sender, address(this), assets);

        IERC20(asset()).approve(vault(), assets);

        // Perform deposit request at first if it's ERC7540
        if (isAsync) IERC7540(vault()).requestDeposit(assets, address(this), address(this));

        // Deposit underlying
        _vault.deposit(assets, address(this));

        // Mint and transfer aToken
        _mint(receiver, amountToMint);

        emit Deposit(sender, receiver, assets, amountToMint);
    }

    /**
     * @dev Withdraws underlying asset from the Vault.
     * @inheritdoc IAutoCompounder
     */
    function withdraw(uint256 aTokenAmount, address receiver) external override returns (uint256 underlyingAmount) {
        require(aTokenAmount > 0, "AutoCompounder: Invalid aToken amount");
        require(receiver != address(0), "AutoCompounder: Invalid receiver address");

        address sender = _msgSender();

        // Calculate underlying amount to withdraw using exchange rate
        underlyingAmount = aTokenAmount.mulDivDown(exchangeRate(), PRECISION);

        // Claim reward before burn
        claimExactUserReward(receiver);

        // Burn aToken
        _burn(sender, aTokenAmount);

        // Withdraw underlying
        _vault.approve(vault(), underlyingAmount);
        _vault.withdraw(underlyingAmount, receiver, address(this));

        emit Withdraw(sender, aTokenAmount, underlyingAmount);
    }

    /**
     * @dev Claims reward from the Vault, swap to underlying and deposit back.
     * @inheritdoc IAutoCompounder
     */
    function claim() external {
        // Check if reward is available
        uint256 reward = IRewards(vault()).getUserReward(address(this), usdc());

        if (reward >= MIN_REWARD) {
            // Claim reward
            IRewards(vault()).claimAllReward(0, address(this));

            // Swap reward for underlying
            IERC20(usdc()).approve(uniswapV2Router(), reward);
            uint256[] memory amounts = _uniswapV2Router.swapExactTokensForTokens(
                reward,
                0, // Accept any amount
                _path,
                address(this),
                block.timestamp + 300 // plus 5 minutes
            );

            // Reinvest swapped underlying
            IERC20(asset()).approve(vault(), amounts[1]);
            _vault.deposit(amounts[1], address(this));

            emit Claim(amounts[1]);
        } else {
            revert InsufficientReward(reward);
        }
    }

    /*///////////////////////////////////////////////////////////////
                        REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Claims exact user reward share from Vault.
     *
     * @param receiver The reward receiver address.
     */
    function claimExactUserReward(address receiver) public {
        require(receiver != address(0), "AutoCompounder: Invalid reward receiver address");

        address sender = _msgSender();
        uint256 userReward = getPendingReward(sender);

        _userClaimedRewards[sender] += userReward;

        IRewards(vault()).claimExactReward(usdc(), receiver, userReward);

        emit UserClaimedReward(sender, receiver, userReward);
    }

    /**
     * @dev Returns pending user reward share from Vault.
     *
     * @param user The compounding participant address.
     * @return pendingReward The pending reward amount.
     */
    function getPendingReward(address user) public view returns (uint256 pendingReward) {
        require(user != address(0), "AutoCompounder: Invalid user address");

        uint256 totalReward = IRewards(vault()).getUserReward(address(this), usdc());

        uint256 entitled = (balanceOf(user) * totalReward) / totalSupply();

        // All reward was claimed
        if (entitled < _userClaimedRewards[user]) return 0;

        pendingReward = entitled - _userClaimedRewards[user];
    }

    /**
     * @dev Returns the exchange rate for token.
     * @inheritdoc IAutoCompounder
     */
    function exchangeRate() public view override returns (uint256) {
        uint256 vTotalSupply = _vault.totalSupply();
        uint256 aTotalSupply = totalSupply();

        return aTotalSupply == 0 ? PRECISION : aTotalSupply.mulDivDown(PRECISION, vTotalSupply);
    }

    /**
     * @dev Returns the underlying asset address.
     */
    function asset() public view override returns (address) {
        return _underlying;
    }

    /**
     * @dev Returns the USDC token address.
     */
    function usdc() public view returns (address) {
        return _usdc;
    }

    /**
     * @dev Returns the Uniswap V2 router address.
     */
    function uniswapV2Router() public view returns (address) {
        return address(_uniswapV2Router);
    }

    /**
     * @dev Returns the corresponding Vault address.
     */
    function vault() public view override returns (address) {
        return address(_vault);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAutoCompounder).interfaceId || super.supportsInterface(interfaceId);
    }
}
