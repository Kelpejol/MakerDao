 // SPDX-License-Identifier: MIT
 pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {NetworkConfig} from "./Config/NetworkConfig.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function run() external returns (uint64) {
        NetworkConfig network = new NetworkConfig();
        ( , ,address vrfCoordinator, , uint256 deployerKey, ) = network
            .activeNetworkConfig();
        return createSubscriptionUsingConfig(vrfCoordinator, deployerKey);
    }

    function createSubscriptionUsingConfig(
        address vrfCoordinator,
        uint256 deployerKey
    ) public returns (uint64) {
        vm.startBroadcast(deployerKey);
        uint64 subId = VRFCoordinatorV2Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        return subId;
    }
}


contract FundSubscription is Script {
    uint96 private constant FUND_AMOUNT = 3 ether;

    function run() external {
        NetworkConfig network = new NetworkConfig();
        (
           ,
            ,
            address vrfCoordinator,
            ,
            uint256 deployerKey,
            uint64 subId
            
        ) = network.activeNetworkConfig();
        fundSubscriptionUsingConfig(vrfCoordinator, deployerKey, subId);
    }

    function fundSubscriptionUsingConfig(
        address vrfCoordinator,
        uint256 deployerKey,
        uint64 subId
    ) public {
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
            subId,
            FUND_AMOUNT
        );
        vm.stopBroadcast();
    }
}

contract AddConsumer is Script {
    function run() external {
        NetworkConfig network = new NetworkConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint256 deployerKey,
            uint64 subId
            
        ) = network.activeNetworkConfig();
        address engine = DevOpsTools.get_most_recent_deployment(
            "Engine",
            block.chainid
        );
        addConsumerUsingConfig(vrfCoordinator, deployerKey, subId, engine);
    }

    function addConsumerUsingConfig(
        address vrfCoordinator,
        uint256 deployerKey,
        uint64 subId,
        address engine
    ) public {
        vm.startBroadcast(deployerKey);
         VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subId, engine);
         vm.stopBroadcast();
    }
}
