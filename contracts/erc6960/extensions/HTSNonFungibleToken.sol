// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { HederaTokenService } from "../../common/hedera/HederaTokenService.sol";
import "../../common/hedera/KeyHelper.sol";
import "../../common/hedera/ExpiryHelper.sol";
import "../../common/hedera/IHRC.sol";
import "../../common/hedera/HederaResponseCodes.sol";

contract HTSNonFungibleToken is HederaTokenService, ExpiryHelper, KeyHelper {
    address private tokenAddress;

    event CreatedToken(address tokenAddress);
    event MintedToken(address tokenAddress, int64 amount, int64 newTotalSupply);
    event BurnedToken(address tokenAddress, int64 amount, int64 newTotalSupply);
    event AssociatedToken(address tokenAddress, address userAddress);

    // Define the HTS precompiled contract interface

    constructor(string memory name, string memory symbol) payable {
        address treasury = address(this);
        string memory memo = "";
        int64 maxSupply = 1000;
        bool freezeDefaultStatus = false;

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](4);
        keys[0] = getSingleKey(KeyType.ADMIN, KeyType.PAUSE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[1] = getSingleKey(KeyType.FREEZE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[2] = getSingleKey(KeyType.SUPPLY, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[3] = getSingleKey(KeyType.WIPE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));

        IHederaTokenService.Expiry memory expiry = IHederaTokenService.Expiry(
            0, treasury, 8000000
        );

        IHederaTokenService.HederaToken memory token = IHederaTokenService.HederaToken(
            name, symbol, treasury, memo, true, maxSupply, freezeDefaultStatus, keys, expiry
        );

        (int responseCode, address contractAddress) = HederaTokenService.createNonFungibleToken(token);

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert ("Error creating Non Fungible Token");
        }

        tokenAddress = contractAddress;

        emit CreatedToken(tokenAddress);

        // associate();
    }

    function _mintHTSToken(address to) internal returns (int64){
        bytes[] memory metadata = new bytes[](1);
        metadata[0] = "https://ipfs.io/ipfs/QmValidHashHere";

        (int responseCode, int64 newTotalSupply, int64[] memory serialNumbers) = HederaTokenService.mintToken(tokenAddress, 0, metadata);

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("Error Minting NFT token");
        }

        emit MintedToken(tokenAddress, 1, newTotalSupply);

        HederaTokenService.transferNFT(tokenAddress, address(this), to, serialNumbers[0]);

        return serialNumbers[0];
    }

    function _burnHTSToken(int64 serialNumber) internal{
        int64[] memory serialNumbers = new int64[](1);
        serialNumbers[0] = serialNumber;

        (int responseCode, int64 newTotalSupply) = HederaTokenService.burnToken(tokenAddress, 1, serialNumbers);

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("Error burning token");
        }

        emit BurnedToken(tokenAddress, 1, newTotalSupply);
    }

    function _isTokenMinted(int64 mainId) internal returns (bool) {
        (int responseCode,) = HederaTokenService.getNonFungibleTokenInfo(tokenAddress, mainId);
        return responseCode == HederaResponseCodes.SUCCESS;
    }

    function associate() public returns (uint256 responseCode) {
        (responseCode) = IHRC(tokenAddress).associate();
        emit AssociatedToken(tokenAddress, msg.sender);
    }

    function associateAccount(address account) public returns (int responseCode) {
        responseCode = HederaTokenService.associateToken(account, tokenAddress);
        emit AssociatedToken(tokenAddress, account);
    }
}
