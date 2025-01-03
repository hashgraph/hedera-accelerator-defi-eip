// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Building} from "./Building.sol";
import {IERC721Metadata} from "../erc721/interface/IERC721Metadata.sol";
import {Token} from '../erc3643/token/Token.sol';

/**
 * @title BuildingFactory
 * @author Hashgraph 
 */
contract BuildingFactory is OwnableUpgradeable  {
    /// @custom:storage-location erc7201:hashgraph.buildings.BuildingFactory
    struct BuildingFactoryStorage {
        address nft;
        address uniswapRouter;
        address uniswapFactory;
        address buildingBeacon;
        BuildingInfo[] buildingsList;
        mapping (address => BuildingInfo) buildingDetails;
    }

    struct BuildingInfo {
        address addr; // building address
        uint256 nftId; // NFT token ID attributed to the building
        string tokenURI; // NFT metadatada location
    }

    //keccak256(abi.encode(uint256(keccak256("hashgraph.buildings.BuildingFactory")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BuildingFactoryStorageLocation = 0x0f40dde8b99b0722537b774c6ef775b5e5a0af035d95bf9802cd87411f806f00;

    function _getBuildingFactoryStorage() private pure returns (BuildingFactoryStorage storage $) {
        assembly {
            $.slot := BuildingFactoryStorageLocation
        }
    }    

    event NewAuditRegistry(address addr);
    event NewBuilding(address addr);

    /**
     * initialize used for upgradable contract
     * @param _nft NFT collection address
     * @param _uniswapRouter unsiswap router address
     * @param _uniswapFactory unsiswap factory address
     */
    function initialize(
        address _nft,
        address _uniswapRouter,
        address _uniswapFactory,
        address _buildingBeacon
    ) public virtual initializer {
        __Ownable_init(_msgSender());
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();
        $.nft = _nft;
        $.uniswapRouter = _uniswapRouter;
        $.uniswapFactory = _uniswapFactory;
        $.buildingBeacon = _buildingBeacon;
    }

    /**
     * getBuildingList get list of buildings deployed
     */
    function getBuildingList() public view returns (BuildingInfo[] memory) {
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();
        return $.buildingsList;
    }

    /**
     * getBuildingDetails get details of building
     * @param buildingAddress address of the building contract 
     */
    function getBuildingDetails(address buildingAddress) public view returns (BuildingInfo memory) {
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();
        return $.buildingDetails[buildingAddress];
    }

    /**
     * newBuilding Creates new building with create2, mints NFT and store it.
     * @param tokenURI metadata location
     */
    function newBuilding(string memory tokenURI) public virtual onlyOwner {
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();
        BeaconProxy buildingProxy = new BeaconProxy(
            $.buildingBeacon,
            abi.encodeWithSelector(Building.initialize.selector, $.uniswapRouter, $.uniswapFactory, $.nft)
        );

        uint256 tokenId = IERC721Metadata($.nft).mint(address(buildingProxy), tokenURI);

        $.buildingDetails[address(buildingProxy)] = BuildingInfo(
            address(buildingProxy),
            tokenId,
            tokenURI
        );

        $.buildingsList.push($.buildingDetails[address(buildingProxy)]);        

        emit NewBuilding(address(buildingProxy));
    }
}
