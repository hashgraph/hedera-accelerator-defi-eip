// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {BuildingFactory} from '../BuildingFactory.sol';

contract BuildingFactoryMock is BuildingFactory {
   
    function version() public pure returns (string memory) {
        return '2.0';
    }

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
    ) public override initializer {
       super.initialize(
            _nft, 
            _uniswapRouter, 
            _uniswapFactory, 
            _onchainIdGateway, 
            _trexGateway, 
            _usdc, 
            _buildingBeacon, 
            _vaultFactory,
            _treasuryBeacon, 
            _governanceBeacon
        );
    }

    function newBuilding(string memory tokenURI) public override {
        super.newBuilding(tokenURI);
    }
}
