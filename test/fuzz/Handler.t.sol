// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {Engine} from "../../src/Engine.sol";
import {NetworkConfig} from "../../script/Config/NetworkConfig.sol";
import {Venom} from "../../src/Venom.sol";
import {Viper} from "../../src/Viper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {WETH} from "../../src/Weth.sol";

contract Handler is Test {

   Engine private immutable i_engine;
   NetworkConfig private immutable i_network;
   Venom private immutable i_venom;
   Viper private immutable i_viper;
   address  weth;
   address pricefeed;
   address i_wallet;

   uint256 private constant MAX_MINT_AMOUNT  = type(uint96).max;
   uint256 private constant INDEX = 0;
   uint256 private constant PRECISION = 1e18;
   uint256 private constant PERCENTAGE = 100;

    constructor(Engine _engine, NetworkConfig _network, Venom _venom, Viper _viper,address _wallet) {
        i_engine = _engine;
        i_network = _network;
        i_venom = _venom;
        i_viper = _viper;
        i_wallet = _wallet;
        (weth, pricefeed,,,,) = _network.activeNetworkConfig();
    }


      function earlyAdoptersDeposit(uint256 _amount, uint256 caller) external {
             uint256 totalAmountDeposited = i_engine.getTotalDeposited();
             uint256 totalTokenToTransfer = i_engine.getTotalTokenToTransfer();
             uint256 endTime = i_engine.getEndTime();
              if(block.timestamp > endTime) {
                return;
              }
            caller = bound(caller, 1, 14);
             uint256 userDepositedBalance = i_engine.getUserDepositBalance(address(uint160(caller)));
             uint256 maxDepositAmount = 300e18 - userDepositedBalance;
             uint256 minDepositAmount = 30e18;
             if(maxDepositAmount < minDepositAmount) {
              return;
             }
            _amount = bound(_amount, minDepositAmount, maxDepositAmount);
             mintDepositors(_amount);
            if(totalAmountDeposited + _amount > totalTokenToTransfer) {
              return;
            }
            vm.startPrank(address(uint160(caller)));
            ERC20(weth).approve(address(i_engine), _amount);
           i_engine.deposit(address(uint160(caller)), _amount);
           vm.stopPrank();
      }


      function mintDepositors(uint256 _amount) internal {
       
        for(uint160 i = 1; i < 15; i++) {
          vm.startPrank(i_wallet);
          WETH(weth).mint(address(i), _amount);
          vm.stopPrank();
        }
       
      }


    function engineDepositCollateral(uint256 _amount, uint256 caller) external {
       caller = bound(caller, 1, 14);
       _amount = bound(_amount, 1, MAX_MINT_AMOUNT);
        mintDepositors(_amount);
        vm.startPrank(address(uint160(caller)));
        ERC20(weth).approve(address(i_engine), _amount);
        i_engine.depositCollateral(address(uint160(caller)), _amount, INDEX);
        vm.stopPrank();
    }



    function engineMintVenom(uint256 _time,  uint256 caller, uint256 _amount) external {
      uint256 minStartAt = i_engine.getEngineStartAt();
      uint256 maxStartAt = type(uint32).max;
     
      _time = bound(_time, minStartAt, maxStartAt);
      vm.warp(block.timestamp + _time);
      vm.roll(block.number + (_time) / 10);
      i_engine.performUpkeep("");
      caller = bound(caller, 1, 14);
       uint256 userCollateralInUsd = i_engine.getCollateralValueInUsd(address(uint160(caller)), INDEX);
       uint256 userMintedBalance = i_engine.getUserMintedBalance(address(uint160(caller)), INDEX);
      uint256 collateralThreshold = i_engine.getThreshold(INDEX);
      uint256 debtCeiling = i_engine.getDebtCeiling();
      if(userCollateralInUsd == 0) {
        return;
      }
      uint256 maxAmountToMint = ((userCollateralInUsd * PRECISION) / (collateralThreshold / PERCENTAGE)) ;
      _amount = bound(_amount, 1, maxAmountToMint);
      if(userMintedBalance + _amount > debtCeiling) {
        return;
      }
      bool userHealthFactor = i_engine._checkHealthFactorIsGood(address(uint160(caller)), _amount, INDEX);
      if(userHealthFactor == false) {
        return;
      }
        vm.startPrank(address(uint160(caller)));
        i_engine.mint( _amount, INDEX);
        vm.stopPrank();
    }

    // There need to be a bound after user has minted because the amount allowed to redeem would gradually reduce as more get minted
    // This is a know issue to be fixed
    function engineRedeemCollateral(uint256 _amount, uint256 caller) external {
     
      caller = bound(caller , 1, 14);
       uint256 userDepositBalance = i_engine.getUserCollateralBalance(address(uint160(caller)), INDEX);
       if(userDepositBalance == 0) {
        return;
       }
      
      _amount = bound(_amount , 1 , userDepositBalance);
      //  bool userHealthFactor = i_engine.checkRedeemCollateralBreaksHealthFactor(address(uint160(caller)), _amount, INDEX);
       bool userMinted = i_engine.getUserMinted(address(uint160(caller)));
       if(userMinted == true) {
        return;
       }
       uint256 collateralThreshold = i_engine.getThreshold(INDEX);
      //  if(userHealthFactor == false) {
      //   return;
      //  }
      
      vm.startPrank(address(uint160(caller)));
      i_engine.redeemCollateral(INDEX, _amount);
      vm.stopPrank();
    }
}