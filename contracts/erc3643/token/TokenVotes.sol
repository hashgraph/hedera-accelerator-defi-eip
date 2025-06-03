// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import {ERC20Upgradeable, IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable, PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ITokenVotes} from "./ITokenVotes.sol";
import {AgentRoleUpgradeable} from "../roles/AgentRoleUpgradeable.sol";
import {IIdentity} from "../../onchainid/interface/IIdentity.sol";
import {IModularCompliance} from "../compliance/modular/IModularCompliance.sol";
import {IIdentityRegistry} from "../registry/interface/IIdentityRegistry.sol";
import {TokenVotesStorage} from "./TokenVotesStorage.sol";

contract TokenVotes is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    ERC20VotesUpgradeable,
    ITokenVotes,
    OwnableUpgradeable,
    AgentRoleUpgradeable,
    TokenVotesStorage
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function init(
        address _identityRegistry,
        address _compliance,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint8 _tokenDecimals,
        address _onchainID // _onchainID can be zero address if not set, can be set later by owner
    ) public initializer {
        require(
            _identityRegistry != address(0)
            && _compliance != address(0)
        , "invalid argument - zero address");
        require(
            keccak256(abi.encode(_tokenName)) != keccak256(abi.encode(""))
            && keccak256(abi.encode(_tokenSymbol)) != keccak256(abi.encode(""))
        , "invalid argument - empty string");
        require(0 <= _tokenDecimals && _tokenDecimals <= 18, "decimals between 0 and 18");

        __ERC20_init(_tokenName, _tokenSymbol);
        __ERC20Votes_init();
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);

        _name = _tokenName;
        _symbol = _tokenSymbol;
        _decimals = _tokenDecimals;
        _tokenOnchainID = _onchainID;
        _tokenPaused = false;
        setIdentityRegistry(_identityRegistry);
        setCompliance(_compliance);
        emit UpdatedTokenInformation(_name, _symbol, 18, _TOKEN_VERSION, _tokenOnchainID);
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function nonces(address owner) public view override(NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }

    function setName(string calldata _tokenName) external override onlyOwner {
        require(keccak256(abi.encode(_tokenName)) != keccak256(abi.encode("")), "invalid argument - empty string");
        _name = _tokenName;
        emit UpdatedTokenInformation(_tokenName, symbol(), decimals(), _TOKEN_VERSION, _tokenOnchainID);
    }
    

    function setSymbol(string calldata _tokenSymbol) external override onlyOwner {
        require(keccak256(abi.encode(_tokenSymbol)) != keccak256(abi.encode("")), "invalid argument - empty string");
        _symbol = _tokenSymbol;
        emit UpdatedTokenInformation(name(), _tokenSymbol ,decimals(), _TOKEN_VERSION, _tokenOnchainID);
    }

    function setOnchainID(address _onchainID) external override onlyOwner {
        require(keccak256(abi.encode(_onchainID)) != keccak256(abi.encode("")), "invalid argument - empty string");
        _tokenOnchainID = _onchainID;
        emit UpdatedTokenInformation(name(), symbol(),decimals(), _TOKEN_VERSION, _onchainID);
    }
    
    function transfer(address _to, uint256 _amount) public override(ERC20Upgradeable, IERC20) whenNotPaused returns (bool) {
        require(!_frozen[_to] && !_frozen[msg.sender], "wallet is frozen");
        require(_amount <= balanceOf(msg.sender) - (_frozenTokens[msg.sender]), "Insufficient Balance");
        if (_tokenIdentityRegistry.isVerified(_to) && _tokenCompliance.canTransfer(msg.sender, _to, _amount)) {
            _transfer(msg.sender, _to, _amount);
            _tokenCompliance.transferred(msg.sender, _to, _amount);
            return true;
        }
        revert("Transfer not possible");
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) public override(ERC20Upgradeable, IERC20) whenNotPaused returns (bool) {
        require(!_frozen[_to] && !_frozen[_from], "wallet is frozen");
        require(_amount <= balanceOf(_from) - (_frozenTokens[_from]), "Insufficient Balance");
        if (_tokenIdentityRegistry.isVerified(_to) && _tokenCompliance.canTransfer(_from, _to, _amount)) {
            address spender = _msgSender();
            _spendAllowance(_from, spender, _amount);
            _transfer(_from, _to, _amount);
            _tokenCompliance.transferred(_from, _to, _amount);
            return true;
        }
        revert("Transfer not possible");
    }

    function setAddressFrozen(address _userAddress, bool _freeze) public override onlyAgent {
        _frozen[_userAddress] = _freeze;
        emit AddressFrozen(_userAddress, _freeze, msg.sender);
    }

    function freezePartialTokens(address _userAddress, uint256 _amount) public override onlyAgent {
        uint256 balance = balanceOf(_userAddress);
        require(balance >= _frozenTokens[_userAddress] + _amount, "Amount exceeds available balance");
        _frozenTokens[_userAddress] = _frozenTokens[_userAddress] + (_amount);
        emit TokensFrozen(_userAddress, _amount);
    }

    function unfreezePartialTokens(address _userAddress, uint256 _amount) public override onlyAgent {
        require(_frozenTokens[_userAddress] >= _amount, "Amount should be less than or equal to frozen tokens");
        _frozenTokens[_userAddress] = _frozenTokens[_userAddress] - (_amount);
        emit TokensUnfrozen(_userAddress, _amount);
    }

    function setIdentityRegistry(address _identityRegistry) public override onlyOwner {
        _tokenIdentityRegistry = IIdentityRegistry(_identityRegistry);
        emit IdentityRegistryAdded(_identityRegistry);
    }

    function setCompliance(address _compliance) public override onlyOwner {
        if (address(_tokenCompliance) != address(0)) {
            _tokenCompliance.unbindToken(address(this));
        }
        _tokenCompliance = IModularCompliance(_compliance);
        _tokenCompliance.bindToken(address(this));
        emit ComplianceAdded(_compliance);
    }

    function forcedTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) public override onlyAgent returns (bool) {
        require(balanceOf(_from) >= _amount, "sender balance too low");
        uint256 freeBalance = balanceOf(_from) - (_frozenTokens[_from]);
        if (_amount > freeBalance) {
            uint256 tokensToUnfreeze = _amount - (freeBalance);
            _frozenTokens[_from] = _frozenTokens[_from] - (tokensToUnfreeze);
            emit TokensUnfrozen(_from, tokensToUnfreeze);
        }
        if (_tokenIdentityRegistry.isVerified(_to)) {
            _transfer(_from, _to, _amount);
            _tokenCompliance.transferred(_from, _to, _amount);
            return true;
        }
        revert("Transfer not possible");
    }

    function mint(address _to, uint256 _amount) public override onlyAgent {
        require(_tokenIdentityRegistry.isVerified(_to), "Identity is not verified.");
        require(_tokenCompliance.canTransfer(address(0), _to, _amount), "Compliance not followed");
        _mint(_to, _amount);
        _tokenCompliance.created(_to, _amount);
    }

    function burn(address _userAddress, uint256 _amount) public override onlyAgent {
        require(balanceOf(_userAddress) >= _amount, "cannot burn more than balance");
        uint256 freeBalance = balanceOf(_userAddress) - _frozenTokens[_userAddress];
        if (_amount > freeBalance) {
            uint256 tokensToUnfreeze = _amount - (freeBalance);
            _frozenTokens[_userAddress] = _frozenTokens[_userAddress] - (tokensToUnfreeze);
            emit TokensUnfrozen(_userAddress, tokensToUnfreeze);
        }
        _burn(_userAddress, _amount);
        _tokenCompliance.destroyed(_userAddress, _amount);
    }

    function recoveryAddress(
        address _lostWallet,
        address _newWallet,
        address _investorOnchainID
    ) external override onlyAgent returns (bool) {
        require(balanceOf(_lostWallet) != 0, "no tokens to recover");
        IIdentity _onchainID = IIdentity(_investorOnchainID);
        bytes32 _key = keccak256(abi.encode(_newWallet));
        if (_onchainID.keyHasPurpose(_key, 1)) {
            uint256 investorTokens = balanceOf(_lostWallet);
            uint256 frozenTokens = _frozenTokens[_lostWallet];
            _tokenIdentityRegistry.registerIdentity(_newWallet, _onchainID, _tokenIdentityRegistry.investorCountry
                (_lostWallet));
            forcedTransfer(_lostWallet, _newWallet, investorTokens);
            if (frozenTokens > 0) {
                freezePartialTokens(_newWallet, frozenTokens);
            }
            if (_frozen[_lostWallet] == true) {
                setAddressFrozen(_newWallet, true);
            }
            _tokenIdentityRegistry.deleteIdentity(_lostWallet);
            emit RecoverySuccess(_lostWallet, _newWallet, _investorOnchainID);
            return true;
        }
        revert("Recovery not possible");
    }

    function batchTransfer(address[] calldata _toList, uint256[] calldata _amounts) external override {
        for (uint256 i = 0; i < _toList.length; i++) {
            transfer(_toList[i], _amounts[i]);
        }
    }

    function batchForcedTransfer(
        address[] calldata _fromList,
        address[] calldata _toList,
        uint256[] calldata _amounts
    ) external override {
        for (uint256 i = 0; i < _fromList.length; i++) {
            forcedTransfer(_fromList[i], _toList[i], _amounts[i]);
        }
    }

    function batchMint(address[] calldata _toList, uint256[] calldata _amounts) external override {
        for (uint256 i = 0; i < _toList.length; i++) {
            mint(_toList[i], _amounts[i]);
        }
    }

    function batchBurn(address[] calldata _userAddresses, uint256[] calldata _amounts) external override {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            burn(_userAddresses[i], _amounts[i]);
        }
    }

    function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external override {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            setAddressFrozen(_userAddresses[i], _freeze[i]);
        }
    }

    function batchFreezePartialTokens(address[] calldata _userAddresses, uint256[] calldata _amounts) external override {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            freezePartialTokens(_userAddresses[i], _amounts[i]);
        }
    }

    function batchUnfreezePartialTokens(address[] calldata _userAddresses, uint256[] calldata _amounts) external override {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            unfreezePartialTokens(_userAddresses[i], _amounts[i]);
        }
    }

    function increaseAllowance(address _spender, uint256 _addedValue) external virtual returns (bool) {
        _approve(msg.sender, _spender, allowance(msg.sender, _spender) + _addedValue);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _decreasedValue) external virtual returns (bool) {
        _approve(msg.sender, _spender, allowance(msg.sender, _spender) - _decreasedValue);
        return true;
    }

    function onchainID() external view override returns (address) {
        return _tokenOnchainID;
    }

    function version() external pure override returns (string memory) {
        return _TOKEN_VERSION;
    }

    function identityRegistry() external view override returns (IIdentityRegistry) {
        return _tokenIdentityRegistry;
    }

    function compliance() external view override returns (IModularCompliance) {
        return _tokenCompliance;
    }

    function paused() public view override(ITokenVotes, PausableUpgradeable) returns (bool) {
        return super.paused();
    }
    
    function isFrozen(address _userAddress) external view override returns (bool) {
        return _frozen[_userAddress];
    }

    function getFrozenTokens(address _userAddress) external view override returns (uint256) {
        return _frozenTokens[_userAddress];
    }

    function name() public view override(ERC20Upgradeable, ITokenVotes) returns (string memory) {
        return _name;
    }

    function symbol() public view override(ERC20Upgradeable, ITokenVotes) returns (string memory) {
        return _symbol;
    }

    function decimals() public view override(ERC20Upgradeable, ITokenVotes) returns (uint8) {
        return _decimals;
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override(ERC20PausableUpgradeable, ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._update(from, to, value);
    }

    function pause() external override onlyAgent whenNotPaused {
        _pause();
        emit Paused(msg.sender);
    }

    /**
     *  @dev See {IToken-unpause}.
     */
    function unpause() external override onlyAgent whenPaused {
        _unpause();
        emit Unpaused(msg.sender);
    }
}
