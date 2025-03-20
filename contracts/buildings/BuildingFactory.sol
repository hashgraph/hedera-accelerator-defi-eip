// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Building} from "./Building.sol";
import {IERC721Metadata} from "../erc721/interface/IERC721Metadata.sol";
import {IdentityGateway} from "../onchainid/gateway/Gateway.sol";
import {BuildingToken} from "./library/BuildingToken.sol";
import {BuildingFactoryStorage} from "./BuildingFactoryStorage.sol";
import {Treasury} from "../treasury/Treasury.sol";
import {BuildingGovernance} from "./governance/BuildingGovernance.sol";
import {IVaultFactory} from "../erc4626/factory/interfaces/IVaultFactory.sol";
import {FeeConfiguration} from "../common/FeeConfiguration.sol";

/**
 * @title BuildingFactory
 * @author Hashgraph 
 */
contract BuildingFactory is BuildingFactoryStorage, Initializable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        address _onchainIdGateway,
        address _trexGateway,
        address _usdc,
        address _buildingBeacon,
        address _vaultFactory,
        address _treasuryBeacon,
        address _governanceBeacon
    ) public virtual initializer {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        $.nft = _nft;
        $.uniswapRouter = _uniswapRouter;
        $.uniswapFactory = _uniswapFactory;
        $.buildingBeacon = _buildingBeacon;
        $.onchainIdGateway = _onchainIdGateway;
        $.trexGateway = _trexGateway;
        $.treasuryBeacon = _treasuryBeacon;
        $.usdc = _usdc;
        $.governanceBeacon = _governanceBeacon;
        $.vaultFactory = _vaultFactory;
        $.vaultNonce = 0;
    }

    /**
     * OnlyBuildingOwner modifier
     * Requires that building address is valid and sender is the building owner
     */
    modifier onlyBuildingOwner(address building) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        require(building != address(0) && $.buildingDetails[building].addr != address(0), "BuildingFactory: Invalid building address");
        require(OwnableUpgradeable(building).owner() == msg.sender, "BuildingFactory: Not building owner");
        _;
    }

    /**
     * getBuildingList get list of buildings deployed
     */
    function getBuildingList() public view returns (BuildingInfo[] memory) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        return $.buildingsList;
    }

    /**
     * getBuildingDetails get details of building
     * @param buildingAddress address of the building contract 
     */
    function getBuildingDetails(address buildingAddress) public view returns (BuildingInfo memory) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        return $.buildingDetails[buildingAddress];
    }

    /**
     * newBuilding Creates new building with create2, mints NFT and store it.
     * @param tokenURI metadata location
     */
    function newBuilding(string memory tokenURI) public virtual {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        BeaconProxy buildingProxy = new BeaconProxy(
            $.buildingBeacon,
            abi.encodeWithSelector(Building.initialize.selector, $.uniswapRouter, $.uniswapFactory, msg.sender)
        );

        // deploy new token
        uint256 nftId = IERC721Metadata($.nft).mint(address(buildingProxy), tokenURI);
        address identity = IdentityGateway($.onchainIdGateway).deployIdentityForWallet(address(buildingProxy));

        $.buildingDetails[address(buildingProxy)] = BuildingInfo(
            address(buildingProxy),
            nftId,
            tokenURI,
            identity,
            address(0), // ERC3643 lazy deploy
            address(0), // treasury lazy deploy
            address(0) // governance lazy deploy
        );

        $.buildingsList.push($.buildingDetails[address(buildingProxy)]);        

        emit NewBuilding(address(buildingProxy), msg.sender);
    }

    /**
     * Create new ERC3643 token
     * @param building address of the building
     * @param name string name of the token
     * @param symbol string symbol of the token
     * @param decimals uint8 token decimals
     */
    function newERC3643Token(address building, string memory name, string memory symbol, uint8 decimals) external onlyBuildingOwner(building) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        require(building != address(0) && $.buildingDetails[building].addr != address(0), "BuildingFactory: Invalid building address");
        require($.buildingDetails[building].erc3643Token == address(0), "BuildingFactory: token already created for building");
        
        address token = BuildingToken.createERC3643Token($.trexGateway, building, name, symbol, decimals);

        OwnableUpgradeable(token).transferOwnership(msg.sender);

        $.buildingDetails[building].erc3643Token = token;

        emit NewERC3643Token(token, building, msg.sender);
    }

    /**
     * Deploy new Treasury for building
     * @param building address of building
     * @param token address of token
     */
    function newTreasury(address building, address token, uint256 reserveAmount, uint256 nPercentage) external onlyBuildingOwner(building) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        require(
            token != address(0) && $.buildingDetails[building].erc3643Token != address(0),
            "BuildingFactory: Invalid token address"
        );
        
        address vault = _deployVault(token, msg.sender);
        address treasury = _deployTreasury(reserveAmount, nPercentage, vault, msg.sender);        
        
        $.buildingDetails[building].treasury = treasury;
        emit NewTreasury(treasury, building, msg.sender);
    }

    /**
     * Deploy new Governance contract for the building
     * @param building address of the building
     * @param name name of the governance
     * @param token token address ( needs to be voting token )
     * @param treasury treasury address
     */
    function newGovernance(address building, string memory name,  address token, address treasury) external onlyBuildingOwner(building) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        require(
            token != address(0) && $.buildingDetails[building].erc3643Token != address(0),
            "BuildingFactory: Invalid token address"
        );

        require(
            treasury != address(0) && $.buildingDetails[building].treasury != address(0),
            "BuildingFactory: Invalid treasury address"
        );

        address governance = _deployGovernance(token, name, treasury, msg.sender); 

        $.buildingDetails[building].governance = governance;
        emit NewGovernance(governance, building, msg.sender);
    }

    /**
     * Deploy new vault
     * @param token address of the token
     */
    function _deployVault(address token, address initialOwner) private  returns (address){
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        
        // increment vault nonce to create salt
        $.vaultNonce++;
    
        string memory salt = IVaultFactory($.vaultFactory).generateSalt(initialOwner, token, $.vaultNonce);
        string memory tokenName = IERC20Metadata(token).name();
        string memory tokenSymbol = IERC20Metadata(token).symbol();

        IVaultFactory.VaultDetails memory vaultDetails = IVaultFactory.VaultDetails(
            token, // address stakingToken;
            tokenName, // string shareTokenName;
            tokenSymbol, // string shareTokenSymbol;
            initialOwner, // address vaultRewardController;
            initialOwner // address feeConfigController;
        );

        FeeConfiguration.FeeConfig memory feeConfig = FeeConfiguration.FeeConfig(
            address(0), // address receiver;
            address(0), // address token;
            0 // uint256 feePercentage;
        );

        return IVaultFactory($.vaultFactory).deployVault(salt, vaultDetails, feeConfig);
    }

    /**
     * Deploy new treasury contract using Beacon Proxy
     * @param reserveAmount reserve amount
     * @param nPercentage  n parcentage
     * @param initialOwner initial owner
     */
    function _deployTreasury(uint256 reserveAmount, uint256 nPercentage, address vault, address initialOwner) private returns (address) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        BeaconProxy treasuryProxy = new BeaconProxy(
            $.treasuryBeacon,
            abi.encodeWithSelector(Treasury.initialize.selector, $.usdc, reserveAmount, nPercentage, vault, initialOwner)
        );

        return address(treasuryProxy);
    }

    /**
     * Deploy new Governance for building
     * @param token building token address
     * @param name governance name
     * @param initialOwner initial owner
     * @param treasury treasury contract address
     */
    function _deployGovernance(address token, string memory name, address treasury, address initialOwner) private returns (address){
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        BeaconProxy governanceProxy = new BeaconProxy(
            $.governanceBeacon,
            abi.encodeWithSelector(BuildingGovernance.initialize.selector, token, name, initialOwner, treasury)
        );

        return address(governanceProxy);
    }
}
