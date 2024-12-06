// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../../common/safe-HTS/SafeHTS.sol";

library BuildingToken {
    using Bits for uint256; // used to create HTS token

    function createHTSToken(string memory _name, string memory _symbol, uint8 decimals, address buildingAddress) internal returns (address _token) {
        uint256 supplyKeyType;
        uint256 adminKeyType;

        IHederaTokenService.KeyValue memory supplyKeyValue;
        supplyKeyType = supplyKeyType.setBit(4);
        supplyKeyValue.delegatableContractId = buildingAddress;

        IHederaTokenService.KeyValue memory adminKeyValue;
        adminKeyType = adminKeyType.setBit(0);
        adminKeyValue.delegatableContractId = buildingAddress;

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](2);

        keys[0] = IHederaTokenService.TokenKey(supplyKeyType, supplyKeyValue);
        keys[1] = IHederaTokenService.TokenKey(adminKeyType, adminKeyValue);

        IHederaTokenService.Expiry memory expiry;
        expiry.autoRenewAccount = buildingAddress;
        expiry.autoRenewPeriod = 8000000;

        IHederaTokenService.HederaToken memory newToken;
        newToken.name = _name;
        newToken.symbol = _symbol;
        newToken.treasury = buildingAddress;
        newToken.expiry = expiry;
        newToken.tokenKeys = keys;
        _token = SafeHTS.safeCreateFungibleToken(newToken, 0, decimals);
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
