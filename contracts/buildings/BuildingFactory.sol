// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Building} from "./Building.sol";
import {IERC721Metadata} from "../erc721/interface/IERC721Metadata.sol";
import {IdentityGateway} from "../onchainid/gateway/Gateway.sol";
import {BuildingToken} from "./library/BuildingToken.sol";
import {BuildingGovernance} from "./governance/BuildingGovernance.sol";

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
        address onchainIdGateway;
        address trexGateway;
        BuildingInfo[] buildingsList;
        mapping (address => BuildingInfo) buildingDetails;
        mapping (address => bool) callableContracts;
    }

    struct BuildingInfo {
        address addr; // building address
        uint256 nftId; // NFT token ID attributed to the building
        string tokenURI; // NFT metadatada location
        address identity; // building's OnchainID identity address
        address erc3643Token; // TRex token
        address governance;
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
    event NewERC3643Token(address building, address token);
    event NewGovernorance(address addr);

    /**
     * initialize used for upgradable contract
     * @param _nft NFT collection address
     * @param _uniswapRouter unsiswap router address
     * @param _uniswapFactory unsiswap factory address
     * @param _buildingBeacon building beacon address
     * @param _onchainIdGateway OnchainID IdentityGateway address
     */
    function initialize(
        address _nft,
        address _uniswapRouter,
        address _uniswapFactory,
        address _buildingBeacon,
        address _onchainIdGateway,
        address _trexGateway
    ) public virtual initializer {
        __Ownable_init(_msgSender());
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();
        $.nft = _nft;
        $.uniswapRouter = _uniswapRouter;
        $.uniswapFactory = _uniswapFactory;
        $.buildingBeacon = _buildingBeacon;
        $.onchainIdGateway = _onchainIdGateway;
        $.trexGateway = _trexGateway;
        
        $.callableContracts[_nft] = true;
        
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
    function newBuilding(string memory tokenURI) public virtual {
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();
        BeaconProxy buildingProxy = new BeaconProxy(
            $.buildingBeacon,
            abi.encodeWithSelector(Building.initialize.selector, $.uniswapRouter, $.uniswapFactory, $.nft)
        );

        uint256 tokenId = IERC721Metadata($.nft).mint(address(buildingProxy), tokenURI);
        address identity = IdentityGateway($.onchainIdGateway).deployIdentityForWallet(address(buildingProxy));

        $.buildingDetails[address(buildingProxy)] = BuildingInfo(
            address(buildingProxy),
            tokenId,
            tokenURI,
            identity,
            address(0), // ERC3643 token lazy deploy
            address(0) // Governor lazy deploy
        );

        $.buildingsList.push($.buildingDetails[address(buildingProxy)]);        

        emit NewBuilding(address(buildingProxy));
    }
    
    /**
     * callFromBuilding inpersonate building and call external contract
     * @param buildingAddress address of the building
     * @param callableContract  address of the external callable contract
     * @param data // encoded function data
     * @notice this allows anyone to execute callable contract function as the building, until ownership/ACL of BuildingFactory is adjusted
     */
    function callFromBuilding(address buildingAddress, address callableContract, bytes memory data) external {
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();
        require($.buildingDetails[buildingAddress].addr == buildingAddress, "BuildingFactory: Invalid building address");
        require($.callableContracts[callableContract] == true, "BuildingFactory: Invalid callable contract");
        Building(buildingAddress).callContract(callableContract, data);
    }

    /**
     * Create new ERC3643 token
     * @param buildingAddress address of the building
     * @param name string name of the token
     * @param symbol string symbol of the token
     */
    function newERC3643Token(address buildingAddress, string memory name, string memory symbol, uint8 decimals) external {
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();

        require(buildingAddress != address(0) && $.buildingDetails[buildingAddress].addr != address(0), "BuildingFactory: Invalid building address");
        require($.buildingDetails[buildingAddress].erc3643Token == address(0), "BuildingFactory: token already created for building");
        
        address token = BuildingToken.createERC3643Token($.trexGateway, buildingAddress, name, symbol, decimals);

        OwnableUpgradeable(token).transferOwnership(msg.sender);

        $.buildingDetails[buildingAddress].erc3643Token = token;

        emit NewERC3643Token(buildingAddress, token);
    }

    /**
     * Create new Governance contract
     * @param buildingAddress address of the building
     */
    function newGovernance(address buildingAddress) external {
        BuildingFactoryStorage storage $ = _getBuildingFactoryStorage();
        require(buildingAddress != address(0) && $.buildingDetails[buildingAddress].addr != address(0), "BuildingFactory: Invalid building address");
        require($.buildingDetails[buildingAddress].erc3643Token != address(0), "BuildingFactory: token not created for building");

        BuildingGovernance governance = new BuildingGovernance();

        governance.initialize(
            $.buildingDetails[buildingAddress].erc3643Token,
            "Building Governance",
            msg.sender,
            address(0) // todo: traasury address
        );

        $.buildingDetails[buildingAddress].governance = address(governance);

        emit NewGovernorance(address(governance));
    }    
}
