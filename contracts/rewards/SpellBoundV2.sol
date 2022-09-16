// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../libraries/ERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

// spell is the neatest bound around. come in with some soul, and leave with some more! 
// handles swapping to and from spell -- our dex reward token.

contract SpellBoundV2 is ERC20("SpellBound", "SPELL"), Ownable, ReentrancyGuard {
    IERC20 public soul;
    IERC20 public seance;
    bool isInitialized; // stores whether contract has been initialized

    // the soul token contract
    function initialize(IERC20 _soul, IERC20 _seance) external onlyOwner {
        require(!isInitialized, 'already started');
        soul = _soul;
        seance = _seance;
        isInitialized = true;
    }

    function totalSeance() public view returns (uint) {
        return seance.balanceOf(address(this));
    }

    function totalSoul() public view returns (uint) {
        return soul.balanceOf(address(this));
    }

    // (total) soul + seance owed to stakers
    function totalPayable() public view returns (uint) {
        uint soulTotal = totalSoul();
        uint seanceTotal = totalSeance();

        return seanceTotal + soulTotal;
    }

    function mintableSpell(uint _seanceStakable) internal view returns (uint) {
        uint spellPower; // initiates spell power

        if (totalPayable() == 0) { spellPower = 1; } // sets a spell power of 1
        else { spellPower = totalSupply() / totalPayable(); } // sets weight for spell power

        return _seanceStakable * spellPower; // sets spell to mint
    }

    // locks soul, mints spell at spell rate
    function enter(uint seanceStakable) external nonReentrant {
        require(isInitialized, 'staking has not yet begun');
        uint spellMintable = mintableSpell(seanceStakable); // total spell to mine to sender
        
        seance.transferFrom(msg.sender, address(this), seanceStakable); // transfers seance from sender
        _mint(msg.sender, spellMintable); // mints spell to sender
    }

    // leaves the spellbound. reclaims soul.
    // unlocks soul rewards + staked seance | burns bounded spell
    function leave(uint spellShare) external nonReentrant {

        // exchange rates
        uint soulRate = totalSoul() / totalSupply(); // soul per spell (exchange rate)
        uint seanceRate = totalSeance() / totalSupply(); // seance per spell (exchange rate)

        // payable component shares
        uint soulShare = spellShare * soulRate; // exchanges spell for soul (at soul rate)
        uint seanceShare = spellShare * seanceRate; // exchanges spell for seance (at soul rate)

        _burn(msg.sender, spellShare);
        soul.transfer(msg.sender, soulShare);
        seance.transfer(msg.sender, seanceShare);
    }



}
