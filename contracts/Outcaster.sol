// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import '@openzeppelin/contracts/access/Ownable.sol';
import './SeanceCircle.sol';

contract Outcaster is Ownable {

    SeanceCircle public immutable seance = SeanceCircle(0x124B06C5ce47De7A6e9EFDA71a946717130079E6);
    event SeanceOutCasted(uint amount);

    function outCast(uint amount) public {
        seance.burn(msg.sender, amount);

        emit SeanceOutCasted(amount);
    }

    function combust() public {
        uint totalSeance = seance.balanceOf(address(this));
        seance.burn(address(this), totalSeance);
        
        emit SeanceOutCasted(totalSeance);
    }

}