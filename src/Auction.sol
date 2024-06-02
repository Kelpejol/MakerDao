// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Engine} from "./Engine.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Venom} from "./Venom.sol";

/**
 * @title A dutch auction
 */

contract Auction is Ownable{
    //// ERROR
    error Auction__NotRequiredAmount();
    error Auction__AuctionExpired(uint256 _endsTime);
    error Auction__TransferToEngineFailed();
    error Auction__TransferToCallerFailed();
    error Auction__TransferRemainingBalanceFailed();

    // CONSTANTS
    uint256 private constant PRECISION = 1e18;

    // IMMUTABLES
    uint256 private immutable i_duration;
    IERC20 private immutable i_collateral;
    address private immutable i_engine;
    uint256 private immutable i_startingPrice;
    uint256 private immutable i_discountRate;
    address private immutable i_venom;


     // STATES
    uint256 private  s_startAt;
    uint256 private  s_endAt;
    uint256 private s_amount;



    /**
     * @param _duration The time length of the auction
     * @param _collateral The address of the collateral to be sold
     * @param _amount The amount to be gotten from the auction in U.S Dollar
     * @param _engine The address of the seller
     * @param _startingPrice The initial price the auction start at
     * @param _discountRate The discount factor which discount the price with time
     * @param _venom The address of the token to be used to purchase collateral
     */
    constructor(
        uint256 _duration,
        address _collateral,
        uint256 _amount,
        address _engine,
        uint256 _startingPrice,
        uint256 _discountRate,
        address _venom
    ) Ownable(_engine) {
        i_duration = _duration;
        i_collateral = IERC20(_collateral);
        s_amount = _amount; 
        i_engine = _engine;
        i_startingPrice = _startingPrice;
        s_startAt = block.timestamp;
        s_endAt = block.timestamp + _duration;
        i_discountRate = _discountRate;
        i_venom = _venom;
    }

   /**
    * @notice The function which returns the price of the collateral to be sold off
    */
    function getPrice() public view returns (uint256) {
        uint256 interval = block.timestamp - s_startAt;
        uint256 rate = i_discountRate * interval;
        return i_startingPrice - rate;
    }


    /**
     * @notice The function called to buy collateral
     * @param _amount The amount of venom the user intends to buy the collateral with
     */

    function buy(uint256 _amount) external {
        if (block.timestamp > s_endAt) {
            revert Auction__AuctionExpired(s_endAt);
        }
        uint256 price = getPrice();
        uint256 amountToTransfer = (_amount * PRECISION) /  price;

       
        if (_amount > s_amount) {
            revert Auction__NotRequiredAmount();
        }
        

        bool success = IERC20(i_venom).transferFrom(
            msg.sender,
            i_engine,
            _amount
        );
        if (!success) {
            revert Auction__TransferToEngineFailed();
        }

        Venom(i_venom).burn(_amount);
        bool successful = IERC20(i_collateral).transfer(msg.sender, amountToTransfer);
        if (!successful) {
            revert Auction__TransferToCallerFailed();
        }
       
       
        s_amount -= _amount;
    }

    /**
     * @notice The function that the engine calls to transfer collateral if there is a  remaining balance after the auction 
     */

    function transferToEngine() external onlyOwner returns(uint256){
        uint256 auctionBalance = i_collateral.balanceOf(address(this));
        bool success = IERC20(i_collateral).transfer(i_engine , auctionBalance);
        if(!success) {
          revert Auction__TransferToEngineFailed();
        }
        return  auctionBalance;
    }

   /**
    * @notice This function update the state of the auction if the intended collateral has not being sold off
    */
    function updatePrice() external onlyOwner {
        s_startAt = block.timestamp;
        s_endAt = block.timestamp + i_duration;
    }

    function getCollateralAmountToLiquidate() external view returns(uint256){
        return s_amount;
    }

    function getStartingTime() external view returns(uint256) {
        return s_startAt;
    }

    function getEndingTime() external view returns(uint256) {
        return s_endAt;
    }

    function getAuctionDuration() external view returns(uint256) {
        return i_duration;
    }

    function getAuctionCollateral() external view returns(IERC20) {
        return i_collateral;
    }

    function getStartingPrice() external view returns(uint256) {
        return i_startingPrice;
    }

    function getDiscountRate() external view returns(uint256) {
        return i_discountRate;
    }

}
