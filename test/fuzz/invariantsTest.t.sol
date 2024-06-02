// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployEngine} from "../../script/DeployEngine.s.sol";
import {Engine} from "../../src/Engine.sol";
import {NetworkConfig} from "../../script/Config/NetworkConfig.sol";
import {Venom} from "../../src/Venom.sol";
import {Viper} from "../../src/Viper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {

    // EARLYADOPTERS --> No matter how much deposited, people cannot claim more than amount of token to be distributed
    DeployEngine deployer;
    Engine engine;
    NetworkConfig network;
    Venom venom;
    Viper viper;
    address weth;
    address pricefeed;
    Handler handler;
    address WALLET_ADDRESS;

     uint256 private constant PRECISION = 1e18;
    
    function setUp() external {
         deployer = new DeployEngine();
        (engine, network, , venom, viper, , WALLET_ADDRESS) = deployer.run();
        (weth, pricefeed,,,,) = network.activeNetworkConfig();
        handler = new Handler(engine, network, venom, viper, WALLET_ADDRESS);
        targetContract(address(handler));
    }

    function invariant_EarlyadoptersCannotHaveMoreTokenClaimThanAmountToDistribute() external view {
        uint256 totalDeposited = Engine(engine).getTotalDeposited();
        uint256 totalamountToClaim = Engine(engine).tokenToTransfer(totalDeposited);
        uint256 totalTokenToTransfer = Engine(engine).getTotalTokenToTransfer();
        assert(totalTokenToTransfer >= totalamountToClaim);
    }


   function invariant_EngineCollateralBalanceMustBeGreaterThanVenom() external view {
        uint256 totalWethBalance = ERC20(weth).balanceOf(address(engine));
        uint256 totalEngineWethValue = Engine(engine).getValueInUsd(totalWethBalance, pricefeed);
        uint256 totalVenomBalance = ERC20(venom).totalSupply();
        if(totalVenomBalance == 0) {
            return;
        }
        uint256 expectedWethToVenomRatio = (totalEngineWethValue * PRECISION) / totalVenomBalance;
        uint256 collateralThreshold = Engine(engine).getThreshold(0) / 100;
        // console.log("totalEngineWethValue :", totalEngineWethValue);
        // console.log("totalVenomBalance :", totalVenomBalance);
        // console.log("collateralThreshold :", collateralThreshold);
        // console.log("expectedWethToVenomRatio :", expectedWethToVenomRatio);
        assert(expectedWethToVenomRatio >= collateralThreshold);
        
   }

}