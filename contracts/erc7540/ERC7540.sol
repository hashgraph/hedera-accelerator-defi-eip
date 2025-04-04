// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {ERC7540Lib, ERC7540_FilledRequest, ERC7540_Request} from "./types/ERC7540Types.sol";

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC7540} from "./interfaces/IERC7540.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ERC7540
 * @author Hashgraph
 *
 * The contract which represents a basic ERC7540 implementation.
 */
abstract contract ERC7540 is ERC4626, IERC7540 {
    using SafeERC20 for IERC20;
    using ERC7540Lib for ERC7540_Request;
    using ERC7540Lib for ERC7540_FilledRequest;

    // Saves the ERC7540 deposit requests when calling `requestDeposit`
    mapping(address => ERC7540_Request) internal _pendingDepositRequest;

    // Saves the ERC7540 redeem requests when calling `requestRedeem`
    mapping(address => ERC7540_Request) internal _pendingRedeemRequest;

    // Saves the result of the deposit after the request has been processed
    mapping(address => ERC7540_FilledRequest) internal _claimableDepositRequest;

    // Saves the result of the redeem after the request has been processed
    mapping(address => ERC7540_FilledRequest) internal _claimableRedeemRequest;

    // ERC7540 operator approvals
    mapping(address controller => mapping(address operator => bool)) public isOperator;

    /**
     * @notice OperatorSet event.
     * @dev Emitted when `controller` gives allowance to `operator`.
     *
     * @param controller The controller address.
     * @param operator The operator address.
     * @param approved The approval status.
     */
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    // Thrown when an unauthorized address attempts to act as a controller
    error InvalidController();

    // Thrown when trying to set an invalid operator, such as setting oneself as an operator
    error InvalidOperator();

    /**
     * @dev Initializes contract with passed parameters.
     *
     * @param _underlying The address of the asset token.
     */
    constructor(IERC20 _underlying) ERC4626(_underlying) {}

    /**
     * @dev Mints shares to receiver by claiming the Request of the controller.
     *
     * @param shares The shares amount to mint.
     * @param receiver The shares receiver.
     * @return assets The assets amount.
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        return mint(shares, receiver, msg.sender);
    }

    /**
     * @dev Mints shares to receiver by claiming the Request of the controller.
     *
     * @param shares The shares amount to mint.
     * @param receiver The shares receiver.
     * @param controller The request controller.
     * @return assets The assets amount.
     */
    function mint(uint256 shares, address receiver, address controller) public virtual returns (uint256 assets) {
        _validateController(controller);
        if (shares > maxMint(controller)) revert ERC4626ExceededMaxMint(receiver, shares, maxMint(controller));
        ERC7540_FilledRequest memory claimable = _claimableDepositRequest[controller];
        assets = claimable.convertToAssets(shares);
        (, assets) = _deposit(assets, shares, receiver, controller);
    }

    /**
     * @dev Mints shares to receiver by claiming the Request of the controller.
     *
     * @param assets The assets to deposit.
     * @param receiver The shares receiver.
     * @return shares The shares amount.
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        return deposit(assets, receiver, msg.sender);
    }

    /**
     * @dev Mints shares to receiver by claiming the Request of the controller.
     *
     * @param assets The assets to deposit.
     * @param receiver The shares receiver.
     * @param controller The Request controller.
     * @return shares The shares amount.
     */
    function deposit(uint256 assets, address receiver, address controller) public virtual returns (uint256 shares) {
        _validateController(controller);
        if (assets > maxDeposit(controller))
            revert MaxDepositRequestExceeded(controller, assets, maxDeposit(controller));
        ERC7540_FilledRequest memory claimable = _claimableDepositRequest[controller];
        shares = claimable.convertToShares(assets);
        (shares, ) = _deposit(assets, shares, receiver, controller);
    }

    function _deposit(
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    ) internal virtual returns (uint256 sharesReturn, uint256 assetsReturn) {
        unchecked {
            _claimableDepositRequest[controller].assets -= assets;
            _claimableDepositRequest[controller].shares -= shares;
        }

        emit Deposit(controller, receiver, assets, shares);

        _mint(receiver, shares);
        return (shares, assets);
    }

    /**
     * @inheritdoc IERC7540
     */
    function requestDeposit(uint256 assets, address controller, address owner) public virtual override {
        require(assets != 0, "AsyncVault: Invalid asset amount");
        require(controller != address(0) && owner != address(0), "AsyncVault: Invalid owner address");

        address sender = isOperator[owner][msg.sender] ? owner : msg.sender;

        _requestDeposit(assets, controller, owner, sender);
    }

    function _requestDeposit(uint256 assets, address controller, address owner, address source) internal virtual {
        _pendingDepositRequest[controller] = _pendingDepositRequest[controller].add(assets);

        IERC20(asset()).safeTransferFrom(source, address(this), assets);

        emit DepositRequested(controller, owner, source, assets);
    }

    /**
     * @dev Claims processed redemption request.
     * @dev Can only be called by controller or approved operator.
     *
     * @param shares The amount of shares to redeem.
     * @param to The assets receiver.
     * @param controller The controller of the redemption request.
     * @return assets The amount of assets returned.
     */
    function redeem(uint256 shares, address to, address controller) public virtual override returns (uint256 assets) {
        _validateController(controller);
        if (shares > maxRedeem(controller)) revert MaxRedeemRequestExceeded(controller, shares, maxRedeem(controller));
        ERC7540_FilledRequest memory claimable = _claimableRedeemRequest[controller];
        assets = claimable.convertToAssets(shares);
        (assets, ) = _withdraw(assets, shares, to, controller);
    }

    /**
     * @dev Claims processed redemption request.
     * @dev Can only be called by controller or approved operator.
     *
     * @param assets The amount of assets to withdraw.
     * @param to The assets receiver.
     * @param controller The controller of the redemption request.
     * @return shares The amount of shares.
     */
    function withdraw(uint256 assets, address to, address controller) public virtual override returns (uint256 shares) {
        _validateController(controller);
        if (assets > maxWithdraw(controller))
            revert ERC4626ExceededMaxWithdraw(controller, assets, maxWithdraw(controller));
        ERC7540_FilledRequest memory claimable = _claimableRedeemRequest[controller];
        shares = claimable.convertToShares(assets);
        (, shares) = _withdraw(assets, shares, to, controller);
    }

    function _withdraw(
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    ) internal virtual returns (uint256 assetsReturn, uint256 sharesReturn) {
        unchecked {
            _claimableRedeemRequest[controller].assets -= assets;
            _claimableRedeemRequest[controller].shares -= shares;
        }

        // Burn shares and transfer assets
        _burn(address(this), shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);

        return (assets, shares);
    }

    /**
     * @inheritdoc IERC7540
     */
    function requestRedeem(uint256 shares, address controller, address owner) public virtual {
        require(shares != 0, "AsyncVault: Invalid shares amount");
        require(controller != address(0) && owner != address(0), "AsyncVault: Invalid owner address");

        address sender = isOperator[owner][msg.sender] ? owner : msg.sender;
        // Create a new request
        _requestRedeem(shares, controller, owner, sender);
    }

    function _requestRedeem(uint256 shares, address controller, address owner, address source) internal virtual {
        _update(source, address(this), shares);

        _pendingRedeemRequest[controller] = _pendingRedeemRequest[controller].add(shares);

        emit RedeemRequested(controller, owner, source, shares);
    }

    /**
     * @dev Hook that is called when processing a deposit request and make it claimable.
     * @dev It assumes user transferred its assets to the contract when requesting a deposit.
     */
    function _fulfillDepositRequest(
        address controller,
        uint256 assetsFulfilled,
        uint256 sharesMinted
    ) internal virtual {
        _pendingDepositRequest[controller] = _pendingDepositRequest[controller].sub(assetsFulfilled);
        _claimableDepositRequest[controller].assets += assetsFulfilled;
        _claimableDepositRequest[controller].shares += sharesMinted;
    }

    /**
     * @dev Hook that is called when processing a redeem request and make it claimable.
     * @dev It assumes user transferred its shares to the contract when requesting a redeem.
     */
    function _fulfillRedeemRequest(
        address controller,
        uint256 sharesFulfilled,
        uint256 assetsWithdrawn
    ) internal virtual {
        _pendingRedeemRequest[controller] = _pendingRedeemRequest[controller].sub(sharesFulfilled);
        _claimableRedeemRequest[controller].assets += assetsWithdrawn;
        _claimableRedeemRequest[controller].shares += sharesFulfilled;
    }

    /**
     * @inheritdoc IERC7540
     */
    function setOperator(address operator, bool approved) external returns (bool success) {
        if (msg.sender == operator) revert InvalidOperator();

        isOperator[msg.sender][operator] = approved;

        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    /**
     * @dev Performs operator and controller permission checks.
     */
    function _validateController(address controller) private view {
        if (msg.sender != controller && !isOperator[controller][msg.sender]) revert InvalidController();
    }

    /**
     * @dev Returns the max possible amount of assets to deposit.
     */
    function maxDeposit(address owner) public view virtual override returns (uint256) {
        return _claimableDepositRequest[owner].assets;
    }

    /**
     * @dev Returns the max possible amount of shares to mint.
     */
    function maxMint(address owner) public view virtual override returns (uint256 shares) {
        return _claimableDepositRequest[owner].shares;
    }

    /**
     * @dev Returns the max possible amount of shares to redeem.
     */
    function maxRedeem(address owner) public view virtual override returns (uint256 shares) {
        return _claimableRedeemRequest[owner].shares;
    }

    /**
     * @dev Returns the max possible amount of assets to withdraw.
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256 assets) {
        return convertToAssets(maxRedeem(owner));
    }

    /**
     * @dev Returns the pending asset amount from the deposit request.
     *
     * @param owner The owner of the request.
     * @return assets The assets amount.
     */
    function pendingDepositRequest(address owner) external view returns (uint256 assets) {
        return _pendingDepositRequest[owner].unwrap();
    }

    /**
     * @dev Returns the pending asset amount from the redeem request.
     *
     * @param owner The owner of the request.
     * @return shares The shares amount.
     */
    function pendingRedeemRequest(address owner) external view returns (uint256 shares) {
        return _pendingRedeemRequest[owner].unwrap();
    }
}
