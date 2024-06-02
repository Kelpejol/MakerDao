pragma solidity ^0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Engine} from "./Engine.sol";




/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale, allowing investors to purchase tokens. This contract includes function to be implemented by the inheriting contract.
 * These functions include:
 * 1) viperBalanceAfterEarlyAdopters() This function get the remaining viper balance of the inheriting contract after the earlyAdopters contract is finishes
 * 2) getReceiverAddress() This function when implemented by the inheriting contract return its address as the receiver
 * 3) transferViper() This function transfer viper from the inheriting contract
 */
 abstract  contract Crowdsale {
     
     // ERRORS
    error Crowdsale__InvalidParams();
    error Crowdsale__PurchaseNotValid(address _investor, uint256 _amount, uint256 _totalInvestorCap, uint256 tokenBalance);
    error Crowdsale__TransferFailed();
    error Crowdsale__TransferViperFailed();
 

   // IMMUTABLES
  address private immutable i_viper;
  address private immutable i_weth;
  uint256 private immutable i_startAt;
  uint256 private immutable i_endTime;
  
   // CONSTANTS
  uint256 private constant INVESTOR_MAX_TOKEN_CAP = 300e18;
  uint256 private constant MIN_WETH_AMOUNT = 3e16;
  uint256 private constant PRECISION = 1e18;


  // EVENTS
  event TokenPurchase(
    address purchaser,
    address indexed beneficiary,
    uint256 indexed value,
    uint256 indexed amount
  );


  

  /**
   * @param _viper The address of the governance token to be sold 
   * @param _startAt The starting time of the crowdsale
   * @param _duration The time length of the crowdsale
   * @param _weth The address of the valid token to be used to purchase viper
   */
  constructor(address _viper, uint256 _startAt, uint256 _duration, address _weth)  {  
    
    i_viper =  _viper;
    i_startAt = block.timestamp + _startAt;
    i_endTime = _duration + i_startAt;
    i_weth = _weth;
  }

 
  

  /**
   * @notice This function issues token to the beneficiary
   * @param _beneficiary The address on behalf of which the token is being bought. A user can buy token on his behalf  by passing in his address
   * @param _amount The amount of weth which is used to purchase the viper
   */
  function buyTokens(address _beneficiary, uint256 _amount) public payable {
    address receiver = getEngineAddress();
     uint256 tokens = getTokenAmount(_amount);
    _preValidatePurchase(_beneficiary, _amount, tokens);
     _forwardWeth(_amount, receiver);
    _processPurchase(_beneficiary, tokens);
    
    emit TokenPurchase(
      msg.sender,
      _beneficiary,
      _amount,
      tokens
    );
   
  }

    function getTokenAmount(uint256 _amount) public view returns(uint256) {
       address receiver = getEngineAddress();
      if(_amount < MIN_WETH_AMOUNT) {
        return 0;
      }
      return _getTokenAmount(_amount, receiver);
    }

 
  /**
   * @dev Validation of an incoming purchase. This function prevalidate an incoming purchase
   */
  function _preValidatePurchase(
    address _beneficiary,
    uint256 _amount,
    uint256 _tokenAmount
  )
    internal view
  {
    address receiver = getEngineAddress();
    uint256 initialToken = Engine(receiver).amountToClaim(_beneficiary);
    uint256 updatedToken = initialToken + _tokenAmount;
    bool validBeneficiary = (_beneficiary != address(0));
    bool validWethAmount = (_amount >= MIN_WETH_AMOUNT);
    bool validTokenAmount = (updatedToken <= INVESTOR_MAX_TOKEN_CAP);
    bool validStartTime = block.timestamp >= i_startAt;
    bool validEndTime = block.timestamp < i_endTime;
    


    bool validParams = (validBeneficiary && validWethAmount && validTokenAmount && validStartTime && validEndTime);
    if(!validParams) {
        revert Crowdsale__PurchaseNotValid(_beneficiary, _amount, INVESTOR_MAX_TOKEN_CAP, updatedToken);
    }
   
  }

  

  /**
   * @notice This function transfer tokens to the beneficiary
   */
  function _deliverTokens(
    address _beneficiary,
    uint256 _tokenAmount
  )
    internal
  {
    transferViper(_beneficiary, _tokenAmount);
  }

  

  /**
   * @notice This function processes token to be delivered to the beneficiary
   */
  function _processPurchase(
    address _beneficiary,
    uint256 _tokenAmount
  )
    internal
  {
    _deliverTokens(_beneficiary, _tokenAmount);
  }

  

  /**
   * @notice This function calculates the amount of token to be transferred based on the amount of weth passed 
   */
  function _getTokenAmount(uint256 _amount, address _receiver)
    internal view  returns (uint256)
  {
    return (_amount * PRECISION) / getPrice(_receiver);
  }

  /**
   * @notice This function foward weth to the receiver address
   */
  function _forwardWeth(uint256 _amount, address _receiver) internal {
    
    bool success =  ERC20(i_weth).transferFrom(msg.sender, _receiver, _amount);
   if(!success) {
    revert Crowdsale__TransferFailed();
   }
  }

  /**
   * @notice This function return price based on the the total weth in the receiver address and the total supply of viper
   */

    function getPrice(address _receiver) internal view returns(uint256){
        uint256 totalWeth = ERC20(i_weth).balanceOf(_receiver);
        uint256 totalViperMinted = ERC20(i_viper).totalSupply();
        uint256 price = (totalWeth * PRECISION) / totalViperMinted;
        return price;
    }

    function getEndTime() public view returns(uint256) {
        return i_endTime;
    }


   


     // --------------------------
     // IMPLEMENTATION FUNCTION
     // --------------------------



function getEngineAddress() internal view virtual returns(address);

   
function transferViper(address _beneficiary, uint256 _amount) internal virtual;
   
}