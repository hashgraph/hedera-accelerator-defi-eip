// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v2;

import {ERC20} from "./ERC20.sol";
import {IHRC} from "../common/hedera/IHRC.sol";

import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IAutoCompounder} from "./interfaces/IAutoCompounder.sol";
import {IERC4626} from "./IERC4626.sol";

import "../common/safe-HTS/SafeHTS.sol";
import "../common/safe-HTS/IHederaTokenService.sol";

/**
 * @title AutoCompounder
 *
 * The contract represents a simple AutoCompounder, that allows to reinvest vault rewards.
 */
contract AutoCompounder is IAutoCompounder, ERC20, Ownable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using Bits for uint256;

    // Vault
    IERC4626 public immutable vault;

    // Underlying token
    address public immutable underlying;

    // Uniswap V2 Router
    IUniswapV2Router02 public uniswapV2Router;

    // AutoCompounder token
    address public aToken;

    // USDC token
    address public usdc;

    // Uniswap swap path to convert from USDC to underlying asset
    address[] internal path;

    // Token balances
    mapping(address token => uint256 balance) public balances;

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param _uniswapV2Router The address of the Uniswap Router contract.
     * @param _vault The Vault contract address.
     * @param _usdc The address of the USDC token.
     * @param _name The aToken name.
     * @param _symbol The aToken symbol.
     */
    constructor(
        address _uniswapV2Router,
        address _vault,
        address _usdc,
        string memory _name,
        string memory _symbol
    ) payable ERC20(_name, _symbol, ERC20(IERC4626(_vault).asset()).decimals()) Ownable(msg.sender) {
        require(_uniswapV2Router != address(0), "TokenBalancer: Invalid Uniswap Router address");
        require(_vault != address(0), "TokenBalancer: Invalid Vault address");
        require(_usdc != address(0), "TokenBalancer: Invalid USDC token address");

        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        underlying = IERC4626(_vault).asset();
        vault = IERC4626(_vault);
        usdc = _usdc;

        path = new address[](2);
        (path[0], path[1]) = (usdc, underlying);

        // Token associations
        SafeHTS.safeAssociateToken(usdc, address(this));
        SafeHTS.safeAssociateToken(underlying, address(this));
        SafeHTS.safeAssociateToken(vault.share(), address(this));

        _createTokenWithContractAsOwner(_name, _symbol, ERC20(underlying));
    }

    function _createTokenWithContractAsOwner(string memory _name, string memory _symbol, ERC20 _underlying) internal {
        uint256 supplyKeyType;
        uint256 adminKeyType;

        IHederaTokenService.KeyValue memory supplyKeyValue;
        supplyKeyType = supplyKeyType.setBit(4);
        supplyKeyValue.delegatableContractId = address(this);

        IHederaTokenService.KeyValue memory adminKeyValue;
        adminKeyType = adminKeyType.setBit(0);
        adminKeyValue.delegatableContractId = address(this);

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](2);

        keys[0] = IHederaTokenService.TokenKey(supplyKeyType, supplyKeyValue);
        keys[1] = IHederaTokenService.TokenKey(adminKeyType, adminKeyValue);

        IHederaTokenService.Expiry memory expiry;
        expiry.autoRenewAccount = address(this);
        expiry.autoRenewPeriod = 8000000;

        IHederaTokenService.HederaToken memory newToken;
        newToken.name = _name;
        newToken.symbol = _symbol;
        newToken.treasury = address(this);
        newToken.expiry = expiry;
        newToken.tokenKeys = keys;
        aToken = SafeHTS.safeCreateFungibleToken(newToken, 0, _underlying.decimals());
        emit CreatedToken(aToken);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deposits staking token to the Vault and returns shares.
     * @inheritdoc IAutoCompounder
     */
    function deposit(uint256 assets) public override returns (uint256 amountToMint) {
        require(assets != 0, "AutoCompounder: Invalid assets amount");

        // Calculate aToken amount to mint using exchange rate
        amountToMint = assets / exchangeRate();

        balances[underlying] += assets;

        SafeHTS.safeTransferToken(underlying, msg.sender, address(this), int64(uint64(assets)));

        SafeHTS.safeApprove(underlying, address(vault), assets);
        vault.deposit(assets, address(this));

        // Mint and transfer aToken
        SafeHTS.safeMintToken(aToken, uint64(amountToMint), new bytes[](0));
        SafeHTS.safeTransferToken(aToken, address(this), msg.sender, int64(uint64(amountToMint)));

        emit Deposit(msg.sender, assets, amountToMint);
    }

    /**
     * @dev Withdraws underlying asset from the Vault.
     * @inheritdoc IAutoCompounder
     */
    function withdraw(uint256 aTokenAmount) external override returns (uint256 underlyingAmount) {
        require(aTokenAmount > 0, "AutoCompounder: Invalid aToken amount");

        // Calculate underlying amount to withdraw using exchange rate
        underlyingAmount = aTokenAmount * exchangeRate();

        balances[underlying] += underlyingAmount;

        // Burn aToken
        SafeHTS.safeTransferToken(aToken, msg.sender, address(this), int64(uint64(aTokenAmount)));
        SafeHTS.safeBurnToken(aToken, uint64(aTokenAmount), new int64[](0));

        // Approve share to burn
        SafeHTS.safeApprove(vault.share(), address(vault), underlyingAmount);
        vault.withdraw(underlyingAmount, address(this), address(this));

        emit Withdraw(msg.sender, aTokenAmount, underlyingAmount);
    }

    /**
     * @dev Claims reward from the Vault, swap to underlying and deposit back.
     * @inheritdoc IAutoCompounder
     */
    function claim() external {
        uint256 reward = vault.getUserReward(address(this), usdc);

        if (reward != 0) {
            vault.claimAllReward(0);

            uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(
                reward,
                0,
                path,
                address(this),
                block.timestamp
            );

            SafeHTS.safeApprove(underlying, address(vault), amounts[1]);
            vault.deposit(amounts[1], address(this));
            emit Claim(amounts[1]);
        } else {
            revert ZeroReward();
        }
    }

    /**
     * @dev Returns the exchange rate: aToken / vToken.
     * @inheritdoc IAutoCompounder
     */
    function exchangeRate() public view returns (uint256) {
        uint256 underlyingTotalSupply = vault.totalAssets();
        return totalSupply == 0 ? 1 : totalSupply / underlyingTotalSupply;
    }

    /**
     * @dev Returns underlying asset address.
     * @inheritdoc IAutoCompounder
     */
    function asset() public view returns (address) {
        return underlying;
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
