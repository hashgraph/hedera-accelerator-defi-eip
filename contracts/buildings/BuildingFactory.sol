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
import {IIdFactory} from "../onchainid/factory/IIdFactory.sol";
import {IIdentity} from "../onchainid/interface/IIdentity.sol";
import {IIdentityRegistry} from "../erc3643/registry/interface/IIdentityRegistry.sol";
import {ITokenVotes} from "../erc3643/token/ITokenVotes.sol";
import {IModularCompliance} from "../erc3643/compliance/modular/IModularCompliance.sol";

interface IOwnable {
    function transferOwnership(address to) external;
}

interface IIdentityGateway {
    function idFactory() external view returns (IIdFactory);
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
        address liquidityPair;
    }

    /**
     * newBuilding Creates new building with create2, mints NFT and store it.
     * @param details NewBuildingDetails struct
     */
    function newBuilding(NewBuildingDetails calldata details) public virtual returns (BuildingDetails memory buildingDetails){
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        
        Tmp memory tmp; // temp var to avoid stack too deep errors
        tmp.initialOwner = msg.sender; // initial owner is sender

        tmp.building = address(new BeaconProxy(
            $.buildingBeacon,
            abi.encodeWithSelector(Building.initialize.selector, $.uniswapRouter, $.uniswapFactory, tmp.initialOwner)
        ));

        // deploy trex token and suite
        tmp.erc3643Token = BuildingTokenLib.detployERC3643Token(
            TokenDetails(
                tmp.initialOwner, 
                $.trexGateway, 
                details.tokenName, 
                details.tokenSymbol, 
                details.tokenDecimals
            )
        );

        // creates the liquidity pair 
        tmp.liquidityPair = Building(tmp.building).createLiquidityPair(tmp.erc3643Token, $.usdc);
        
        // deploy treasury
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
        
        // deploy vault
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

        // deploy governance
        tmp.governance = BuildingGovernanceLib.deployGovernance(
            GovernanceDetails(
                $.governanceBeacon, 
                tmp.erc3643Token, 
                details.governanceName, 
                tmp.treasury, 
                tmp.initialOwner
            )
        );

        // deploy autocompounder
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

        IIdentityGateway identityGateway = IIdentityGateway($.onchainIdGateway);
        IIdentityRegistry identityRegistry = IIdentityRegistry(ITokenVotes(tmp.erc3643Token).identityRegistry());
        address[] memory controllers = getControllerAddresses(tmp);

        for (uint256 i = 0; i < controllers.length; i++) {
            IIdentity identity = IIdentity(identityGateway.idFactory().getIdentity(controllers[i]));
            uint16 country = 840; // defaults to united states (ISO code)

            if (identity == IIdentity(address(0))) { 
                // if controller does not have identity, create one.
                identity = IIdentity(identityGateway.deployIdentityForWallet(controllers[i]));
            }

            if (identityRegistry.identity(controllers[i]) == IIdentity(address(0))) {
                // if identity is not registered, register it.
                identityRegistry.registerIdentity(
                    controllers[i],
                    identity,
                    country
                );

                emit IdentityRegistered(tmp.building, controllers[i], address(identity), country);
            }
        }

        tmp.nftId = IERC721Metadata($.nft).mint(tmp.building, details.tokenURI);        
        ITreasury(tmp.treasury).grantGovernanceRole(tmp.governance);
        ITreasury(tmp.treasury).addVault(tmp.vault); 
        IAccessControl(tmp.vault).grantRole(keccak256("VAULT_REWARD_CONTROLLER_ROLE"), tmp.treasury);// grant reward controller role to treasury
        IOwnable(tmp.vault).transferOwnership(tmp.initialOwner);
        IERC20(tmp.erc3643Token).mint(tmp.initialOwner, details.tokenMintAmount);
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

    /**
     *  deployIdentityForWallet 
     * @param wallet address to deploy the identity to
     * @return identity address
     */
    function deployIdentityForWallet(address wallet) external returns (address) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        return IIdentityGateway($.onchainIdGateway).deployIdentityForWallet(wallet);
    }

    /**
     * registerIdentity 
     * Register the identity in the Identity Registry
     * @param buildingAddress address
     * @param wallet wallet address
     * @param country uint26 country code
     */
    function registerIdentity(address buildingAddress, address wallet, uint16 country) external {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        BuildingDetails memory building = $.buildingDetails[buildingAddress];
        ITokenVotes token = ITokenVotes(building.erc3643Token);
        IIdFactory idFactory = IIdentityGateway($.onchainIdGateway).idFactory();
        IIdentityRegistry ir = token.identityRegistry();
        address identity = idFactory.getIdentity(wallet);

        require(identity != address(0), "Identity for wallet not found");

        ir.registerIdentity(wallet, IIdentity(identity), country);

        emit IdentityRegistered(buildingAddress, wallet, identity, country);
    }

    /**
     * getIdentity
     * @param wallet wallet address
     * @return IIdentity identity of the wallet if any
     */
    function getIdentity(address wallet) external view returns (IIdentity) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();
        IIdFactory idFactory = IIdentityGateway($.onchainIdGateway).idFactory();

        return IIdentity(idFactory.getIdentity(wallet));
    }

    /**
     * return an arreay of addresses that might interacto with the erc3643 token;
     * erc3643 tokens might be sent to them, so they need to have identities registered
     * @param tmp temporary state variable
     */
    function getControllerAddresses(Tmp memory tmp) private view returns (address[] memory controllers) {
        BuildingFactoryStorageData storage $ = _getBuildingFactoryStorage();

        uint8 NUM_CONTROLLERS = 6;
        controllers = new address[](NUM_CONTROLLERS);

        controllers[0] = tmp.initialOwner;
        controllers[1] = tmp.vault;
        controllers[2] = tmp.autoCompounder;
        controllers[3] = tmp.building;
        controllers[4] = $.uniswapRouter;
        controllers[5] = tmp.liquidityPair;
        // controllers[5] = tmp.oneSidedExchange;
    }
}
