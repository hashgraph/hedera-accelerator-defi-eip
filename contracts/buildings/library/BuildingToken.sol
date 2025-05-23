// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {ITREXGateway} from "../../erc3643/factory/ITREXGateway.sol";
import {ITREXFactory} from "../../erc3643/factory/ITREXFactory.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

struct TokenDetails {
    address trexGateway; 
    address buildingAddress; 
    string name;
    string symbol;
    uint8 decimals;
}

library BuildingTokenLib {

    function detployERC3643Token(TokenDetails memory details) external returns (address) {
        // use simple ERC20 tokens for now, this will be replaced later to ERC3643 token
        ITREXGateway(trexGateway).deployTREXSuite(
            buildTokenDetails(owner, name, symbol, decimals), 
            buildTokenClaimDetails()
        );

        string memory salt  = string(abi.encodePacked(Strings.toHexString(owner), name));
        address factory = ITREXGateway(trexGateway).getFactory();
        
        token = ITREXFactory(factory).getToken(salt);
    }

    function buildTokenDetails(address owner, string memory name, string memory symbol, uint8 decimals) internal pure returns (ITREXFactory.TokenDetails memory)  {
        address irs = address(0);
        address onchainid = address(0);
        address[] memory irsAgents = new address[](0);
        address[] memory tokenAgents = new address[](0);
        address[] memory complianceModules = new address[](0);
        bytes[] memory complianceSettings = new bytes[](0);
        
        return ITREXFactory.TokenDetails(
            owner,
            name,
            symbol,
            decimals,
            irs,
            onchainid, 
            irsAgents, 
            tokenAgents, 
            complianceModules, 
            complianceSettings 
        );
    }

    function buildTokenClaimDetails () internal pure returns (ITREXFactory.ClaimDetails memory) {
        uint256[] memory claimTopics = new uint256[](0);
        address[] memory issuers = new address[](0);
        uint256[][] memory  issuerClaims = new uint256[][](0);
        
        return ITREXFactory.ClaimDetails (
            claimTopics,
            issuers,
            issuerClaims
        );
    }
}
