// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../common/hedera/IHederaTokenService.sol";
import "../common/hedera/KeyHelper.sol";
import "../common/hedera/ExpiryHelper.sol";
import "../common/hedera/IHRC.sol";
import "../common/hedera/HederaResponseCodes.sol";

contract HTSToken is ExpiryHelper, KeyHelper {
    address public tokenAddress;
    address private constant HEDERA_TOKEN_SERVICE = address(0x167);

    event CreatedToken(address tokenAddress);
    event MintedToken(address tokenAddress, int64 amount, int64 newTotalSupply);
    event AssociatedToken(address tokenAddress, address userAddress);

    // Define the HTS precompiled contract interface
    IHederaTokenService hts = IHederaTokenService(HEDERA_TOKEN_SERVICE);

    constructor(string memory tokenName, string memory tokenSymbol, int32 decimals) payable {
        address treasury = address(this);
        string memory memo = "";
        int64 initialTotalSupply = 0;
        int64 maxSupply = 10000; // TODO: no max supply
        bool freezeDefaultStatus = false;

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](5);
        keys[0] = getSingleKey(KeyType.ADMIN, KeyType.PAUSE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[1] = getSingleKey(KeyType.KYC, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[2] = getSingleKey(KeyType.FREEZE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[3] = getSingleKey(KeyType.WIPE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[4] = getSingleKey(KeyType.SUPPLY, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));

        IHederaTokenService.Expiry memory expiry = IHederaTokenService.Expiry(0, treasury, 8000000);

        IHederaTokenService.HederaToken memory token = IHederaTokenService.HederaToken(
            tokenName,
            tokenSymbol,
            treasury,
            memo,
            true,
            maxSupply,
            freezeDefaultStatus,
            keys,
            expiry
        );

        (int responseCode, address createdTokenAddress) = hts.createFungibleToken{value: msg.value}(
            token,
            initialTotalSupply,
            decimals
        );

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("HTSToken: Error creating fungible token");
        }

        tokenAddress = createdTokenAddress;

        emit CreatedToken(createdTokenAddress);
    }

    function mint(int64 amount) public returns (int responseCode, int64 newTotalSupply, int64[] memory serialNumbers) {
        (responseCode, newTotalSupply, serialNumbers) = hts.mintToken(tokenAddress, amount, new bytes[](0));

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("Error minting token");
        }

        emit MintedToken(tokenAddress, amount, newTotalSupply);

        hts.transferToken(tokenAddress, address(this), msg.sender, amount);
    }

    function associate() public returns (uint256 responseCode) {
        (responseCode) = IHRC(tokenAddress).associate();
        emit AssociatedToken(tokenAddress, msg.sender);
    }
}
