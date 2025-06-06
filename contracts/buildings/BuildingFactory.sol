// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Building} from "./Building.sol";
import {IERC721Metadata} from "../erc721/interface/IERC721Metadata.sol";
import {BuildingFactoryStorage} from "./BuildingFactoryStorage.sol";
import {ITreasury} from "../treasury/interfaces/ITreasury.sol";
import {BuildingVaultLib, VaultDetails} from "./library/BuildingVault.sol";
import {BuildingGovernanceLib, GovernanceDetails} from "./library/BuildingGovernance.sol";
import {BuildingTreasuryLib, TreasuryDetails} from "./library/BuildingTreasury.sol";
import {BuildingTokenLib, TokenDetails} from "./library/BuildingToken.sol";
import {BuildingAutoCompounderLib, AutoCompounderDetails} from "./library/BuildingAutoCompounder.sol";

interface IOwnable {
    function transferOwnership(address to) external;
}

interface IIdentityGateway {
    function deployIdentityForWallet(address wallet) external returns (address);
}

interface IERC20 {
    function mint(address to, uint256 amount) external;
}
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
        address autoCompounder;
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
        tmp.identity = IIdentityGateway($.onchainIdGateway).deployIdentityForWallet(tmp.building);
        tmp.erc3643Token = BuildingTokenLib.detployERC3643Token(
            TokenDetails(
                $.trexGateway, 
                tmp.building, 
                details.tokenName, 
                details.tokenSymbol, 
                details.tokenDecimals
            )
        );
        tmp.treasury = BuildingTreasuryLib.deployTreasury(
            TreasuryDetails(
                $.treasuryBeacon, 
                tmp.initialOwner, 
                details.treasuryReserveAmount, 
                details.treasuryNPercent, 
                tmp.initialOwner, // business address
                $.usdc,
                address(this) // building factory
            )
        );

        tmp.vault = BuildingVaultLib.deployVault(
            VaultDetails(
                tmp.erc3643Token,
                details.vaultShareTokenName, 
                details.vaultShareTokenSymbol, 
                details.vaultFeeReceiver, 
                details.vaultFeeToken, 
                details.vaultFeePercentage,
                tmp.initialOwner, // rewardController
                tmp.initialOwner, // feeConfigController
                details.vaultCliff, 
                details.vaultUnlockDuration
            )
        );        
        tmp.governance = BuildingGovernanceLib.deployGovernance(
            GovernanceDetails(
                $.governanceBeacon, 
                tmp.erc3643Token, 
                details.governanceName, 
                tmp.treasury, 
                tmp.initialOwner
            )
        );

        tmp.autoCompounder = BuildingAutoCompounderLib.deployAutoCompounder(
            AutoCompounderDetails (
                $.uniswapRouter,
                tmp.vault,
                $.usdc,
                details.aTokenName,
                details.aTokenSymbol,
                tmp.initialOwner // operator
            )
        );

        ITreasury(tmp.treasury).grantGovernanceRole(tmp.governance);
        ITreasury(tmp.treasury).addVault(tmp.vault); 
        IAccessControl(tmp.vault).grantRole(keccak256("VAULT_REWARD_CONTROLLER_ROLE"), tmp.treasury);// grant reward controller role to treasury
        IOwnable(tmp.vault).transferOwnership(tmp.initialOwner);
        IERC20(tmp.erc3643Token).mint(tmp.initialOwner, details.tokenMintAmount);
        IOwnable(tmp.erc3643Token).transferOwnership(tmp.initialOwner);
        IOwnable(tmp.autoCompounder).transferOwnership(tmp.initialOwner);

        buildingDetails = BuildingDetails(
            tmp.building,
            tmp.nftId,
            details.tokenURI,
            tmp.identity,
            tmp.erc3643Token,
            tmp.treasury, 
            tmp.governance,
            tmp.vault,
            tmp.autoCompounder
        );

        $.buildingDetails[tmp.building] = buildingDetails;
        $.buildingsList.push(buildingDetails);

        emit NewBuilding(tmp.building, tmp.erc3643Token, tmp.treasury, tmp.vault, tmp.governance, tmp.initialOwner, tmp.autoCompounder);
    }
}
