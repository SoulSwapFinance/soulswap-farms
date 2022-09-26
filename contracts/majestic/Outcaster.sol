// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

// import '@openzeppelin/contracts/access/Ownable.sol';
import '../tokens/SeanceCircle.sol';

contract Outcaster {

    SeanceCircle public immutable seance = SeanceCircle(0x124B06C5ce47De7A6e9EFDA71a946717130079E6);
    
    uint public totalContributions;

    event SeanceOutCasted(uint amount);

    function outCast(uint amount) public {
        seance.burn(msg.sender, amount);
        totalContributions += amount;

        emit SeanceOutCasted(amount);
    }

    function combust() public {
        uint amount = seance.balanceOf(address(this));
        seance.burn(address(this), amount);
        totalContributions += amount;

        emit SeanceOutCasted(amount);
    }

}