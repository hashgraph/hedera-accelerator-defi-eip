// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Treasury
 * @author Hashgraph
 * @notice This contract manages the Treasury
 */

interface IVault {
    function deposit(uint256 amount) external;
}

interface IToken {
    function identityRegistry() external view returns (address);
}

contract Treasury is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    IERC20 public usdc;
    IERC20 public buildingToken; // ERC3643 Token
    IVault public vault;
    uint256 public reserveAmount;

    uint256 public nPercentage; // N% USDC back to business
    uint256 public mPercentage; // M% USDC held in building treasury

    address public businessAddress;

    event Deposit(address indexed from, uint256 amount);
    event Payment(address indexed to, uint256 amount);
    event ExcessFundsForwarded(uint256 amount);
    event FundsDistributed(uint256 toBusiness, uint256 toTreasury);

    constructor(
        address _usdcAddress,
        address _buildingTokenAddress,
        address _vaultAddress,
        uint256 _reserveAmount,
        uint256 _nPercentage,
        address _businessAddress,
        address governanceAddress
    ) {
        require(_usdcAddress != address(0), "Invalid USDC address");
        require(_buildingTokenAddress != address(0), "Invalid token address");
        require(_vaultAddress != address(0), "Invalid Vault address");
        require(_businessAddress != address(0), "Invalid business address");
        require(governanceAddress != address(0), "Invalid governance address");
        require(_nPercentage <= 10000, "Invalid N percentage"); // Basis points
        require(_reserveAmount > 0, "Reserve amount must be greater than zero");

        usdc = IERC20(_usdcAddress);
        buildingToken = IERC20(_buildingTokenAddress);
        vault = IVault(_vaultAddress);
        reserveAmount = _reserveAmount;
        nPercentage = _nPercentage;
        mPercentage = 10000 - _nPercentage; // N + M = 100% (in basis points)
        businessAddress = _businessAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, governanceAddress);
        _grantRole(GOVERNANCE_ROLE, governanceAddress);
    }

    // deposit USDC into treasury
    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
        
        _distributeFunds(amount);
    }

    function _distributeFunds(uint256 amount) internal {
        uint256 toBusiness = (amount * nPercentage) / 10000;
        uint256 toTreasury = amount - toBusiness;

        // N% to business
        usdc.safeTransfer(businessAddress, toBusiness);

        emit FundsDistributed(toBusiness, toTreasury);

        _forwardExcessFunds();

    }

    // governance-controlled function to make payments
    function makePayment(address to, uint256 amount) external onlyRole(GOVERNANCE_ROLE) {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than zero");
        uint256 balance = usdc.balanceOf(address(this));
        require(balance >= amount, "Insufficient funds");

        usdc.safeTransfer(to, amount);
        emit Payment(to, amount);

        _forwardExcessFunds();
    }

    // update reserve amount (governance role)
    function setReserveAmount(uint256 newReserveAmount) external onlyRole(GOVERNANCE_ROLE) {
        require(newReserveAmount > 0, "Reserve amount must be greater than zero");
        reserveAmount = newReserveAmount;
        _forwardExcessFunds();
    }

    function _forwardExcessFunds() internal {
        uint256 balance = usdc.balanceOf(address(this));
        if (balance > reserveAmount) {
            uint256 excessAmount = balance - reserveAmount;
            usdc.safeIncreaseAllowance(address(vault), excessAmount);
            vault.deposit(excessAmount);
            emit ExcessFundsForwarded(excessAmount);
        }
    }
}
