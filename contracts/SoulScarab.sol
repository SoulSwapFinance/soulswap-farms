// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './libraries/SafeERC20.sol';
import './Outcaster.sol';

contract SoulScarab {

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
    uint public tributeRate = enWei(10);        // 10%
    
    event Withdraw(address recipient, uint amount);
    event ScarabSummoned(uint amount, uint id);
    event ManifestorUpdated(address manifestor);
        
    function lockSouls(address _recipient, uint _amount, uint _unlockTimestamp) external returns (uint id) {
        require(_amount > 0, 'Insufficient SOUL balance.');
        require(_unlockTimestamp <= block.timestamp + 365 days, 'Unlock must be within one year.');
        require(_unlockTimestamp > block.timestamp, 'Unlock is not in the future.');
        require(soul.allowance(msg.sender, address(this)) >= _amount, 'Approve SOUL first.');

        // soul balance [before the deposit]
        uint beforeDeposit = soul.balanceOf(address(this));

        // transfers your soul into a Scarab
        soul.transfer(address(this), _amount);

        // soul balance [after the deposit]
        uint afterDeposit = soul.balanceOf(address(this));
        
        // safety precaution (requires contract recieves SOUL)
        _amount = afterDeposit - beforeDeposit; 

        // calulates tribute amount
        uint _tribute = getTribute(_amount);
                
        walletBalance[msg.sender] += _amount;
        
        // create a new id, based off deposit count
        id = ++depositsCount;
        scarabs[id].recipient = _recipient;
        scarabs[id].amount = _amount;
        scarabs[id].tribute = _tribute;
        scarabs[id].unlockTimestamp = _unlockTimestamp;
        scarabs[id].withdrawn = false;
        
        depositsByRecipient[_recipient].push(id);

        emit ScarabSummoned(_amount, id);
        
        return id;
    }
    
    
    function withdrawTokens(uint id) external {
        require(block.timestamp >= scarabs[id].unlockTimestamp, 'Tokens are still locked.');
        require(msg.sender == scarabs[id].recipient, 'You are not the recipient.');
        require(scarabs[id].withdrawn, 'Tokens are already withdrawn.');
        
        scarabs[id].withdrawn = true;
        
        walletBalance[msg.sender] -= scarabs[id].amount;

        // [1] acquires tribute amount
        uint tribute = getTribute(scarabs[id].amount);
        
        // [2] burns tribute to enable recipient to claim
        seance.transfer(address(this), tribute);
        outcaster.outCast(tribute);

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
        require(amount > 0, 'cannot have zero fee');
        return amount * tributeRate / 100;
    }
    
    function getDepositsByRecipient(address _recipient) view external returns (uint[] memory) { return depositsByRecipient[_recipient]; }
    function getTotalLockedBalance() view external returns (uint) { return soul.balanceOf(address(this)); }
    
    function enWei(uint amount) public pure returns (uint) { return amount * 1E18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1E18; }
}
