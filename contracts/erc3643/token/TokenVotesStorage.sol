// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;
import "../compliance/modular/IModularCompliance.sol";
import "../registry/interface/IIdentityRegistry.sol";

contract TokenVotesStorage {
    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    address internal _tokenOnchainID;
    string internal constant _TOKEN_VERSION = "4.1.3";

    /// @dev Variables of freeze and pause functions
    mapping(address => bool) internal _frozen;
    mapping(address => uint256) internal _frozenTokens;
    bool internal _tokenPaused = false;

    /// @dev Identity Registry contract used by the onchain validator system
    IIdentityRegistry internal _tokenIdentityRegistry;

    /// @dev Compliance contract linked to the onchain validator system
    IModularCompliance internal _tokenCompliance;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[49] private __gap;
}
