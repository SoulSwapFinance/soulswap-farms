// SPDX-License-Identifier: MIT

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import './libs/ERC20.sol';

pragma solidity ^0.8.0;

// This contract handles swapping to and from SPELL, SoulSwap's staking token.
contract SpellBound is ERC20("SpellBound", "SPELL"), Ownable {
    IERC20 public soul;

    constructor(IERC20 _soul) {
        soul = _soul;
    }

    // Have a spell bound your SOUL to earn SPELL.
    // Locks SOUL and mints SPELL.
    function enter(uint256 _amount) public {
        // Gets the amount of SOUL locked in the contract
        uint256 totalSoul = soul.balanceOf(address(this));
        // Gets the amount of SPELL in existence
        uint256 totalShares = totalSupply();
        // Lock the SOUL in the contract (prevents reentrancy)
        soul.transferFrom(msg.sender, address(this), _amount);
        // If no SPELL exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalSoul == 0) {
            _mint(msg.sender, _amount);
        } 
        // Calculate and mint the amount of SPELL the SOUL is worth. 
        // The ratio will change overtime, as SPELL is burned/minted and SOUL deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount * (totalShares) / (totalSoul);
            _mint(msg.sender, what);
        }
    }

    // Break the Spell. Clam back your SOUL.
    // => Claim Back Your SOUL.
    function leave(uint256 _share) public {
        // Gets the amount of SPELL in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of SOUL the SPELL is worth
        uint256 what = _share * (soul.balanceOf(address(this))) / (totalShares);
        _burn(msg.sender, _share);
        soul.transfer(msg.sender, what);
    }
}