// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v2;

import {ERC20} from "./ERC20.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC7540} from "../erc7540/interfaces/IERC7540.sol";

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IAutoCompounder} from "./interfaces/IAutoCompounder.sol";
import {IRewards} from "./interfaces/IRewards.sol";

/**
 * @title AutoCompounder
 *
 * The contract represents a simple AutoCompounder, that allows to reinvest vault rewards.
 */
contract AutoCompounder is IAutoCompounder, ERC20, Ownable, ERC165 {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    using Bits for uint256;

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

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param uniswapV2Router_ The address of the Uniswap Router contract.
     * @param vault_ The Vault contract address.
     * @param usdc_ The address of the USDC token.
     * @param name_ The aToken name.
     * @param symbol_ The aToken symbol.
     */
    constructor(
        address uniswapV2Router_,
        address vault_,
        address usdc_,
        string memory name_,
        string memory symbol_,
        address operator_
    ) payable ERC20(name_, symbol_, ERC20(IERC4626(vault_).asset()).decimals()) Ownable(msg.sender) {
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

        // Calculate aToken amount to mint using exchange rate
        amountToMint = assets / exchangeRate();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        IERC20(asset()).approve(vault(), assets);

        // Perform deposit request at first if it's ERC7540
        if (isAsync) IERC7540(vault()).requestDeposit(assets, address(this), address(this));

        // Deposit underlying
        _vault.deposit(assets, address(this));

        // Mint and transfer aToken
        _mint(receiver, amountToMint);

        emit Deposit(receiver, assets, amountToMint);
    }

    /**
     * @dev Withdraws underlying asset from the Vault.
     * @inheritdoc IAutoCompounder
     */
    function withdraw(uint256 aTokenAmount, address receiver) external override returns (uint256 underlyingAmount) {
        require(aTokenAmount > 0, "AutoCompounder: Invalid aToken amount");
        require(receiver != address(0), "AutoCompounder: Invalid receiver address");

        // Calculate underlying amount to withdraw using exchange rate
        underlyingAmount = aTokenAmount * exchangeRate();

        // Burn aToken
        _burn(msg.sender, aTokenAmount);

        // Withdraw underlying with rewards
        _vault.approve(vault(), underlyingAmount);
        _vault.withdraw(underlyingAmount, receiver, address(this));

        emit Withdraw(msg.sender, aTokenAmount, underlyingAmount);
    }

    /**
     * @dev Claims reward from the Vault, swap to underlying and deposit back.
     * @inheritdoc IAutoCompounder
     */
    function claim() external {
        // Check if reward is available
        uint256 reward = IRewards(vault()).getUserReward(address(this), usdc());

        if (reward != 0) {
            // Claim reward
            IRewards(vault()).claimAllReward(0, address(this));

            // Swap reward for underlying
            IERC20(usdc()).approve(uniswapV2Router(), reward);
            uint256[] memory amounts = _uniswapV2Router.swapExactTokensForTokens(
                reward,
                0, // Accept any amount
                _path,
                address(this),
                block.timestamp
            );

            // Reinvest swapped underlying
            IERC20(asset()).approve(vault(), amounts[1]);
            _vault.deposit(amounts[1], address(this));

            emit Claim(amounts[1]);
        } else {
            revert ZeroReward();
        }
    }

    /**
     * @dev Returns the exchange rate for token.
     * @inheritdoc IAutoCompounder
     */
    function exchangeRate() public view override returns (uint256) {
        uint256 vTotalSupply = _vault.totalSupply();
        uint256 aTotalSupply = totalSupply();

        return aTotalSupply == 0 ? 1 : aTotalSupply / vTotalSupply;
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
