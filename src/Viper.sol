// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.21;


import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";


contract Viper is ERC20, ERC20Permit, ERC20Votes, Ownable{
    constructor()
        ERC20("Viper", "VPR")
        ERC20Permit("Viper")
        Ownable(msg.sender)
    {
       _mint(msg.sender, 10000e18);
    }

    // The following functions are overrides required by Solidity.

    function mint(address _beneficiary, uint256 _amount) external onlyOwner {
        _mint(_beneficiary, _amount);
    }

     function burn(address _beneficiary, uint256 _amountToBurn) external  onlyOwner {
        _burn(_beneficiary, _amountToBurn);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

  
}
