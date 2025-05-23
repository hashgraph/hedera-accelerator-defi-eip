// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Building} from "./Building.sol";
import {IERC721Metadata} from "../erc721/interface/IERC721Metadata.sol";
import {IdentityGateway} from "../onchainid/gateway/Gateway.sol";
import {BuildingToken} from "./library/BuildingToken.sol";
import {BuildingFactoryStorage} from "./BuildingFactoryStorage.sol";
import {Treasury} from "../treasury/Treasury.sol";
import {BuildingGovernance} from "./governance/BuildingGovernance.sol";
import {FeeConfiguration} from "../common/FeeConfiguration.sol";
import {ITreasury} from "../treasury/interfaces/ITreasury.sol";
import {BasicVault} from "../erc4626/BasicVault.sol";

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
    }

    /**
     * getBuildingList get list of buildings deployed
     */
    function getBuildingList() public view returns (BuildingDetails[] memory) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        return $.buildingsList;
    }

    /**
     * getBuildingDetails get details of building
     * @param buildingAddress address of the building contract
     */
    function getBuildingDetails(address buildingAddress) public view returns (BuildingDetails memory) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        return $.buildingDetails[buildingAddress];
    }

    // Temporary struct to handle new building variables
    // used to avoid stack too deep error.
    struct Tmp {
        address initialOwner;
        address building;
        uint256 nftId;
        address identity;
        address erc3643Token;
        address treasury;
        address vault;
        address governance;
    }

    /**
     * newBuilding Creates new building with create2, mints NFT and store it.
     * @param details NewBuildingDetails struct
     */
    function newBuilding(NewBuildingDetails calldata details) public virtual returns (BuildingDetails memory buildingDetails){
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        
        Tmp memory tmp; // temp var to avoid stack too deep errors

        tmp.building = address(new BeaconProxy(
            $.buildingBeacon,
            abi.encodeWithSelector(Building.initialize.selector, $.uniswapRouter, $.uniswapFactory, msg.sender)
        ));

        // deploy new token
        tmp.initialOwner = msg.sender;
        tmp.nftId = IERC721Metadata($.nft).mint(tmp.building, details.tokenURI);
        tmp.identity = IdentityGateway($.onchainIdGateway).deployIdentityForWallet(tmp.building);
        tmp.erc3643Token = _deployERC3643Token(tmp.initialOwner, details.tokenName, details.tokenSymbol, details.tokenDecimals);
        tmp.treasury = _deployTreasury(details.treasuryReserveAmount, details.treasuryNPercent, tmp.initialOwner);
        
        tmp.vault = _deployVault(
            tmp.erc3643Token, 
            details.vaultShareTokenName, 
            details.vaultShareTokenSymbol, 
            tmp.initialOwner, // details.vaultRewardController, 
            tmp.initialOwner, // details.vaultFeeConfigController, 
            details.vaultFeeReceiver, 
            details.vaultFeeToken, 
            details.vaultFeePercentage, 
            details.vaultCliff, 
            details.vaultUnlockDuration
        );
        
        tmp.governance = _deployGovernance(tmp.erc3643Token, details.governanceName, tmp.treasury, tmp.initialOwner);
        
        ITreasury(tmp.treasury).grantGovernanceRole(tmp.governance);
        ITreasury(tmp.treasury).addVault(tmp.vault);
        
        // grant reward controller role to treasury
        IAccessControl(tmp.vault).grantRole(BasicVault(tmp.vault).VAULT_REWARD_CONTROLLER_ROLE(), tmp.treasury);

        buildingDetails = BuildingDetails(
            tmp.building,
            tmp.nftId,
            details.tokenURI,
            tmp.identity,
            tmp.erc3643Token,
            tmp.treasury, 
            tmp.governance,
            tmp.vault 
        );

        $.buildingDetails[tmp.building] = buildingDetails;
        $.buildingsList.push(buildingDetails);

        emit NewBuilding(tmp.building, tmp.erc3643Token, tmp.treasury, tmp.vault, tmp.governance, tmp.initialOwner);
    }

    /**
     * Create new ERC3643 token
     * @param owner address of the owner
     * @param name string name of the token
     * @param symbol string symbol of the token
     * @param decimals uint8 token decimals
     */
    function _deployERC3643Token(
        address owner,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) private returns (address token) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        token = BuildingToken.createERC3643Token($.trexGateway, owner, name, symbol, decimals);
    }

    function _deployVault(
        address token,
        string memory tokenName,
        string memory tokenSymbol,
        address rewardController,
        address feeConfigController,
        address feeReceiver,
        address feeToken,
        uint256 feePercentage,
        uint32 cliff,
        uint32 unlockDuration
    ) private returns (address vault) {
        FeeConfiguration.FeeConfig memory feeConfig = FeeConfiguration.FeeConfig(
            feeReceiver, // address receiver;
            feeToken, // address token;
            feePercentage // uint256 feePercentage;
        );

        vault = address(new BasicVault(
            IERC20(token),
            tokenName,
            tokenSymbol,
            feeConfig,
            rewardController,
            feeConfigController,
            cliff,
            unlockDuration
        ));
    }

    /**
     * Deploy new treasury contract using Beacon Proxy
     * @param reserveAmount reserve amount
     * @param nPercentage  n parcentage
     * @param initialOwner initial owner
     */
    function _deployTreasury(
        uint256 reserveAmount,
        uint256 nPercentage,
        address initialOwner
    ) private returns (address) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        // initial owner as business address
        address businessAddress = initialOwner;

        BeaconProxy treasuryProxy = new BeaconProxy(
            $.treasuryBeacon,
            abi.encodeWithSelector(
                Treasury.initialize.selector,
                $.usdc,
                reserveAmount,
                nPercentage,
                initialOwner,
                businessAddress,
                address(this)
            )
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
    function _deployGovernance(
        address token,
        string memory name,
        address treasury,
        address initialOwner
    ) private returns (address) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        BeaconProxy governanceProxy = new BeaconProxy(
            $.governanceBeacon,
            abi.encodeWithSelector(BuildingGovernance.initialize.selector, token, name, initialOwner, treasury)
        );

        return address(governanceProxy);
    }
}
