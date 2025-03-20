// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract BuildingFactoryStorage {
    /// @custom:storage-location erc7201:hashgraph.buildings.BuildingFactory
    struct BuildingFactoryStorageData {
        address nft;
        address uniswapRouter;
        address uniswapFactory;
        address buildingBeacon;
        address onchainIdGateway;
        address trexGateway;
        address treasuryBeacon;
        address usdc;
        address governanceBeacon;
        address vaultFactory;
        uint256 vaultNonce;
        BuildingInfo[] buildingsList;
        mapping (address => BuildingInfo) buildingDetails;
    }

    struct BuildingInfo {
        address addr; // building address
        uint256 nftId; // NFT token ID attributed to the building
        string tokenURI; // NFT metadatada location
        address identity; // building's OnchainID identity address
        address erc3643Token; // TRex token
        address treasury;
        address governance;
    }

    //keccak256(abi.encode(uint256(keccak256("hashgraph.buildings.BuildingFactory")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BuildingFactoryStorageLocation = 0x0f40dde8b99b0722537b774c6ef775b5e5a0af035d95bf9802cd87411f806f00;

    function _getBuildingFactoryStorage() internal pure returns (BuildingFactoryStorageData storage $) {
        assembly {
            $.slot := BuildingFactoryStorageLocation
        }
    }

    event NewAuditRegistry(address addr);
    event NewBuilding(address addr, address initialOwner);
    event NewERC3643Token(address token, address building, address initialOwner);
    event NewTreasury(address treasury, address building, address initialOwner);
    event NewGovernance(address governance, address building, address initialOwner);
}
