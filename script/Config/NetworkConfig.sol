// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../../test/Mocks/MockV3Aggregator.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../../test/Mocks/LinkToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Viper} from "../../src/Viper.sol";
import {Venom} from "../../src/Venom.sol";
import {WETH} from "../../src/Weth.sol";

contract NetworkConfig is Script {
    Network public activeNetworkConfig;

    uint8 private constant DECIMALS = 8;
    int256 private constant ANSWER = 3500e8;
    uint96 private constant BASE_FEE = 0.25 ether;
    uint96 private constant GAS_PRICE_LINK = 1e9;
    uint256 private constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 private DEPLOYER_KEY = vm.envUint("PRIVATE_KEY");

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        }
        activeNetworkConfig = getOrCreateAnvilEthConfig();
    }
       
    
       

    struct Network {
        address weth;
        address pricefeed;
        address vrfCoordinator;
        address link;
        uint256 deployerKey;
        uint64 subId;
    }

    function getSepoliaEthConfig() internal returns (Network memory) {

       vm.startBroadcast(DEPLOYER_KEY);
       WETH weth = new WETH();
       vm.stopBroadcast();

        Network memory sepoliaEthconfig = Network({
            weth: address(weth),
            pricefeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            deployerKey: DEPLOYER_KEY,
            subId: 9730
        });
        return sepoliaEthconfig;
    }

    function getOrCreateAnvilEthConfig() internal returns (Network memory) {
        if (activeNetworkConfig.pricefeed != address(0)) {
            return activeNetworkConfig;
        }

       vm.startBroadcast(DEFAULT_ANVIL_KEY);
        MockV3Aggregator priceFeed = new MockV3Aggregator(DECIMALS, ANSWER);
        VRFCoordinatorV2Mock vrfcoordinator = new VRFCoordinatorV2Mock(
            BASE_FEE,
            GAS_PRICE_LINK
        );
        LinkToken link = new LinkToken();
        ERC20Mock weth = new ERC20Mock();
        vm.stopBroadcast();
        Network memory anvilEthConfig = Network({
           
            weth: address(weth),
            pricefeed: address(priceFeed),
            vrfCoordinator: address(vrfcoordinator),
            link: address(link),
            deployerKey: DEFAULT_ANVIL_KEY,
            subId: 0

        });
        return anvilEthConfig;
    }

    

   
}
