// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract WETH is ERC20, ERC20Burnable, Ownable{
    using SafeERC20 for ERC20;

    constructor() ERC20("Wrapped ETH", "WETH") Ownable(msg.sender){}

    function mint(address _beneficiary, uint256 _amount) external onlyOwner {
        _mint(_beneficiary, _amount);
    }
// 0x966b99b84329E3b1d1AdAEa6815e93DC9f540b22 WETH


}