// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";



contract Venom is ERC20, Ownable, ERC20Burnable{

    error Venom__InvalidAddress();
    error Venom__CanOnlyMintMoreThanZero();
    error Venom__CanOnlyBurnMoreThanZero();
    error Venom__SenderHasNoBalance();
    
    /**
     * VENOM -> The name of the stable coin
     * VNM -> The symbol of the stable coin
     */

     

    constructor() ERC20("VENOM", "VNM") Ownable(msg.sender){
    }

    /**
     * 
     * @param _to The address to which the stable coin is  minted to
     * @param _amountToMint The amount minted to the given address
     */


    function mint(address _to, uint256 _amountToMint) external onlyOwner returns(bool) {

        if(_to == address(0)) {
            revert Venom__InvalidAddress();
        }

        if(_amountToMint <= 0) {
            revert Venom__CanOnlyMintMoreThanZero();
        }
        _mint(_to, _amountToMint);
        return true;
    }

    /**
     * 
     * @param _amountToBurn The amount of the stable coin to be removed from the system
     */

    function burn(uint256 _amountToBurn) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if(balance == 0) {
            revert Venom__SenderHasNoBalance();
        }

        if(_amountToBurn <= 0) {
            revert Venom__CanOnlyBurnMoreThanZero();
        }
        super.burn(_amountToBurn);
        
    }


 

   //0x6C03bCe9e81A81F7b36c055B992A22D77628de83
}