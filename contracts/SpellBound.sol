// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import './libs/ERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './libs/Operable.sol';

// spell is the neatest bound around. come in with some soul, and leave with some more! 
// handles swapping to and from spell -- our dex reward token.

contract SpellBound is ERC20("SpellBound", "SPELL"), Operable, ReentrancyGuard {
    IERC20 public soul;

    bool isInitialized; // stores whether contract has been initialized

    // the soul token contract
    function initialize(IERC20 _soul) external onlyOwner {
        soul = _soul;
        isInitialized = true;
    }

    // locks soul, mints spell at bound rate
    function enter(uint soulQty) external nonReentrant {
        require(isInitialized, 'staking has not yet begun');
        // acquires soul locked in the contract
        uint totalSoul = soul.balanceOf(address(this));
        // acquires spellBound in existence
        uint totalBound = totalSupply();
        // if no spellBound exists, mint it 1:1 to soul recieves
        if (totalBound == 0 || totalSoul == 0) { _mint(msg.sender, soulQty); }
        // calc & mint spellBound qty the soul is worth
        // the ratio will change overtime
            // spellBound is burned / minted
            // soul fees deposited + deposited soul + withdrawn soul
        else {
            uint boundRate = totalBound / totalSoul; // qty of bound : quantity of soul in contract
            uint boundQty = soulQty * boundRate;
            _mint(msg.sender, boundQty);
        }
        // locks the soul in the contract
        soul.transferFrom(msg.sender, address(this), soulQty);
    }

    // leaves the spellbound. reclaims soul.
    // unlocks soul rewards + staked | burns bounded spell
    function leave(uint spellQty) external nonReentrant {
        require(isInitialized, 'staking has not yet begun');
        // qty of spellBound in existence
        uint totalBound = totalSupply();
        // calcs the qty of soul the spell is worth
        uint boundRate = soul.balanceOf(address(this)) / totalBound;
        uint rewards = spellQty * boundRate;
        _burn(msg.sender, spellQty);
        soul.transfer(msg.sender, rewards);
    }

    // sends over soul that is shared across all spell bounded | operators-only, ywc
    // does not mint new spell
    function boundSpell(uint soulQty) external nonReentrant onlyOperator {
        require(isInitialized, 'staking has not yet begun');
        // locks the soul in the contract
        soul.transferFrom(msg.sender, address(this), soulQty);
    }

}
