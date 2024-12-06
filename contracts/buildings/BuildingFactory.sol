// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Building} from "./Building.sol";
import {IERC721Metadata} from "../erc721/interface/IERC721Metadata.sol";
import {Token} from '../erc3643/token/Token.sol';

contract BuildingFactory is OwnableUpgradeable  {
    address private nft;
    address private uniswapRouter;
    address private uniswapFactory;
    address private router;

    event NewBuilding(address addr);

    function initialize(
        address _nft,
        address _uniswapRouter,
        address _uniswapFactory
    ) external initializer {
        __Ownable_init(_msgSender());
        nft = _nft;
        uniswapRouter = _uniswapRouter;
        uniswapFactory = _uniswapFactory;
        router = _uniswapRouter;
    }

    function newBuilding(bytes32 _salt) external payable {
        Building building = (new Building){salt: _salt}();

        building.initialize{ value : msg.value }(
            _salt,
            uniswapRouter, 
            uniswapFactory,
            nft
        );

        IERC721Metadata(nft).mint(address(building), ""); // tokenURI should be sent here?        
        emit NewBuilding(address(building));
    }

    function addLiquidityToBuilding(
        address _building, 
        address _tokenA,
        uint256 _tokenAAmount, 
        address _tokenB, 
        uint256 _tokenBAmount
    ) external payable {
        IERC20(_tokenA).transferFrom(_msgSender(), address(_building), _tokenAAmount);
        IERC20(_tokenB).transferFrom(_msgSender(), address(_building), _tokenBAmount);
        Building(_building).addLiquidity{ value : msg.value}(_tokenA, _tokenAAmount, _tokenB, _tokenBAmount);
    }
}
