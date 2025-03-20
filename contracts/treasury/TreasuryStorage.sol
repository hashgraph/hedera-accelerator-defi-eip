// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract TreasuryStorage {
    /// @custom:storage-location erc7201:hashgraph.treasury.TreasuryStorage
    struct TreasuryData {
        address usdc;
        address buildingToken; // ERC3643 Token
        address vault;
        uint256 reserveAmount;
        uint256 nPercentage; // N% USDC back to business
        uint256 mPercentage; // M% USDC held in building treasury
        address businessAddress;
    }

    //keccak256(abi.encode(uint256(keccak256("hashgraph.treasury.TreasuryStorage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant TreasuryStorageLocation = 0x72a4ccd47996c0aa9e54efd606e03b13bee57794bd0974b6dda8fcd457f37700;

    function _getTreasuryStorage() internal pure returns (TreasuryData storage $) {
        assembly {
            $.slot := TreasuryStorageLocation
        }
    } 

    event Deposit(address indexed from, uint256 amount);
    event Payment(address indexed to, uint256 amount);
    event ExcessFundsForwarded(uint256 amount);
    event FundsDistributed(uint256 toBusiness, uint256 toTreasury);
}
