// SPDX-License-Identifier: MIT

import '@openzeppelin/contracts/access/Ownable.sol';
import './libs/ERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';

pragma solidity ^0.8.0;

contract SpellBound is ERC20("SpellBound", "SPELL"), Ownable {
    IERC20 public soul;

    constructor(IERC20 _soul) {
        soul = _soul;
    }

    // Enter the bound (somewhere lost between the simulacra and simulation). 
    // Pay some SOUL. Collect some shares.
    function enter(uint256 _amount) public {
        uint256 totalSoul = soul.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        if (totalShares == 0 || totalSoul == 0) {
            _mint(msg.sender, _amount);
        } else {
            uint256 what = _amount * (totalShares) / (totalSoul);
            _mint(msg.sender, what);
        }
        soul.transferFrom(msg.sender, address(this), _amount);
    }

    // Leave the Bound? 
    // => Claim Back Your SOUL.
    function leave(uint256 _share) public {
        uint256 totalShares = totalSupply();
        uint256 what = _share * (soul.balanceOf(address(this))) / (totalShares);
        _burn(msg.sender, _share);
        soul.transfer(msg.sender, what);
    }
}