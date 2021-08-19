// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import 'hardhat/console.sol';

contract MockToken is ERC20("MockToken", "MT") {
    function mintTo(address account, uint256 amount) public  {
        _mint(account, amount);
        console.log("minting '%s' %s", amount / 1e18, "tokens");
    }

    function mint(uint256 amount) public  {
        _mint(msg.sender, amount);
        console.log("minting '%s' %s", amount / 1e18, "tokens");
    }
}