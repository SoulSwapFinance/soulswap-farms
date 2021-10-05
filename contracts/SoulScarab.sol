// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './libraries/SafeERC20.sol';
import './Outcaster.sol';

contract SoulScarab {
    using SafeERC20 for IERC20;

    SeanceCircle public immutable seance = SeanceCircle(0x124B06C5ce47De7A6e9EFDA71a946717130079E6);
    SoulPower public immutable soul = SoulPower(0xe2fb177009FF39F52C0134E8007FA0e4BaAcBd07);

    Outcaster public immutable outcaster = Outcaster(0xce530f22d82A2437F2fb4b43Df0e1e4fD446f0ff);

    struct Scarab {
        address recipient;
        uint amount;
        uint tribute;
        uint unlockTimestamp;
        bool withdrawn;
    }
    
    uint public depositsCount;
    mapping (address => uint[]) public depositsByRecipient;
    mapping (uint => Scarab) public scarabs;
    mapping (address => uint) public walletBalance;
    
    address public manifestor = msg.sender;
    uint public tributeRate = 10; // 10%
    
    event Withdraw(address recipient, uint amount);
    event ScarabSummoned(uint amount, uint id);
    event ManifestorUpdated(address manifestor);
        
    function lockSouls(address _recipient, uint _amount, uint _unlockTimestamp) external returns (uint id) {
        require(_amount > 0, 'Insufficient SOUL amount.');
        require(_unlockTimestamp > block.timestamp, 'Unlock is not in the future.');

        // soul balance [before the deposit]
        // uint beforeDeposit = soul.balanceOf(address(this));

        // transfers your soul into a Scarab
        soul.transferFrom(msg.sender, address(this), _amount);

        // soul balance [after the deposit]
        // uint afterDeposit = soul.balanceOf(address(this));
        
        // safety precaution (would be a negative number -> i.e, 90 - 100)
        // _amount = afterDeposit - beforeDeposit; 

        // calulates tribute amount
        uint _tribute = getTribute(_amount);
                
        walletBalance[msg.sender] += _amount;
        
        // create a new id, based off deposit count
        id = ++depositsCount;
        scarabs[id].recipient = _recipient;
        scarabs[id].amount = _amount;
        scarabs[id].tribute = _tribute;
        scarabs[id].unlockTimestamp = _unlockTimestamp;
        
        depositsByRecipient[_recipient].push(id);

        emit ScarabSummoned(_amount, id);
        
        return id;
    }
        
    function withdrawTokens(uint id) external {
        require(block.timestamp >= scarabs[id].unlockTimestamp, 'Tokens are still locked.');
        require(msg.sender == scarabs[id].recipient, 'You are not the recipient.');
        require(!scarabs[id].withdrawn, 'Tokens are already withdrawn.');
        
        scarabs[id].withdrawn = true;
        
        walletBalance[msg.sender] -= scarabs[id].amount;

        // [1] acquires tribute amount
        uint tribute = getTribute(scarabs[id].amount);
        
        // [2] burns tribute to enable recipient to claim
        seance.transferFrom(msg.sender, address(outcaster), tribute);

        // [3] transfers soul to the sender
        soul.transfer(msg.sender, scarabs[id].amount);

        emit Withdraw(msg.sender, scarabs[id].amount);  
    }
    
    function setManifestor(address _manifestor) external {
        require(msg.sender == manifestor, 'You are not the current manifestor');
        manifestor = _manifestor;

        emit ManifestorUpdated(manifestor);
    }

    function getTribute(uint amount) public view returns (uint fee) {
        require(amount > 0, 'Amount must not be 0');
        // i.e., 200 * 10 / 100 = 20
        return amount * tributeRate / 100;
    }
    
    function getDepositsByRecipient(address _recipient) view external returns (uint[] memory) {
        return depositsByRecipient[_recipient];
    }
    
    function getTotalLockedBalance() view external returns (uint) {
       return soul.balanceOf(address(this));
    }
}
