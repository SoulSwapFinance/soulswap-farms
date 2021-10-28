// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './libraries/SafeERC20.sol';
import './Outcaster.sol';

contract SoulScarab {

    SeanceCircle public immutable seance = SeanceCircle(0x124B06C5ce47De7A6e9EFDA71a946717130079E6);
    SoulPower public immutable soul = SoulPower(0xe2fb177009FF39F52C0134E8007FA0e4BaAcBd07);

    Outcaster public immutable outcaster = Outcaster(0xce530f22d82A2437F2fb4b43Df0e1e4fD446f0ff);

    struct Scarab {
        IERC20 token;
        address recipient;
        uint amount;
        uint tribute;
        uint unlockTimestamp;
        bool withdrawn;
    }
    
    uint public depositsCount;
    mapping (address => uint[]) public depositsByRecipient;
    mapping (address => uint[]) private depositsByTokenAddress;

    mapping (uint => Scarab) public scarabs;
    mapping (address => uint) public walletBalance;
    mapping (address => mapping(address => uint)) public walletTokenBalance;
    
    uint public tributeRate = 10;        // 10%
    
    event Withdraw(address recipient, uint amount);
    event Repossesed(address recipient, uint amount);
    event Saved(address recipient, uint amount);
    event ScarabSummoned(uint amount, uint id);
        
    function lockSouls(address _recipient, uint _amount, uint _unlockTimestamp) external returns (uint id) {
        require(_amount > 0, 'Insufficient SOUL balance.');
        require(_unlockTimestamp <= block.timestamp + 365 days, 'Unlock must be within one year.');
        require(_unlockTimestamp > block.timestamp, 'Unlock is not in the future.');
        require(soul.allowance(msg.sender, address(this)) >= _amount, 'Approve SOUL first.');

        // soul balance [before the deposit]
        uint beforeDeposit = soul.balanceOf(address(this));

        // transfers your soul into a Scarab
        soul.transferFrom(msg.sender, address(this), _amount);

        // soul balance [after the deposit]
        uint afterDeposit = soul.balanceOf(address(this));
        
        // safety precaution (requires contract recieves SOUL)
        _amount = afterDeposit - beforeDeposit; 

        // calulates tribute amount
        uint _tribute = getTribute(_amount);
                
        walletBalance[_recipient] += _amount;
        walletTokenBalance[address(soul)][_recipient] = walletTokenBalance[address(soul)][_recipient] + _amount;
        
        // create a new id, based off deposit count
        id = ++depositsCount;
        scarabs[id].token = soul;
        scarabs[id].recipient = _recipient;
        scarabs[id].amount = _amount;
        scarabs[id].tribute = _tribute;
        scarabs[id].unlockTimestamp = _unlockTimestamp;
        scarabs[id].withdrawn = false;
        
        depositsByRecipient[_recipient].push(id);
        depositsByTokenAddress[address(soul)].push(id);

        emit ScarabSummoned(_amount, id);
        
        return id;
    }
    
    function withdrawTokens(uint id) public {
        require(block.timestamp >= scarabs[id].unlockTimestamp, 'Tokens are still locked.');
        require(msg.sender == scarabs[id].recipient, 'You are not the recipient.');
        require(!scarabs[id].withdrawn, 'Tokens are already withdrawn.');
        seance.approve(address(this), scarabs[id].amount);
        scarabs[id].withdrawn = true;
        
        walletBalance[msg.sender] -= scarabs[id].amount;
        walletTokenBalance[address(soul)][msg.sender] -= scarabs[id].amount;


        // [1] acquires tribute amount
        uint tribute = getTribute(scarabs[id].amount);
        
        // [2] burns tribute to enable recipient to claim
        seance.transferFrom(msg.sender, address(this), tribute);
        outcaster.outCast(tribute);

        // [3] transfers soul to the sender
        soul.transfer(msg.sender, scarabs[id].amount);

        emit Withdraw(msg.sender, scarabs[id].amount);  
    }
    
    function claimUnclaimed(uint id) public {
        require(block.timestamp >= scarabs[id].unlockTimestamp + 60 days, 'Tokens are still within claims period.');
        require(!scarabs[id].withdrawn, 'Tokens are already withdrawn.');
        seance.approve(address(this), scarabs[id].amount);

        address recipient = scarabs[id].recipient;
        walletBalance[recipient] -= scarabs[id].amount;
        walletTokenBalance[address(soul)][recipient] -= scarabs[id].amount;

        // [1] acquires tribute amount
        uint tribute = getTribute(scarabs[id].amount);
        
        // [2] burns tribute to enable you to claim.
        seance.transferFrom(msg.sender, address(this), tribute);
        outcaster.outCast(tribute);

        // [3] transfers soul to the sender.
        soul.transfer(msg.sender, scarabs[id].amount);

        emit Repossesed(msg.sender, scarabs[id].amount);  

    }
    
    function savingGrace(uint id) public {
        require(block.timestamp >= scarabs[id].unlockTimestamp, 'Tokens are still locked.');
        require(block.timestamp <= scarabs[id].unlockTimestamp + 90 days, 'Tokens are no longer within claims period.');
        require(!scarabs[id].withdrawn, 'Tokens are already withdrawn.');
        seance.approve(address(this), scarabs[id].amount);

        address recipient = scarabs[id].recipient;
        
        walletBalance[recipient] -= scarabs[id].amount;
        walletTokenBalance[address(soul)][recipient] -= scarabs[id].amount;

        // [1] acquires tribute amount.
        uint tribute = getTribute(scarabs[id].amount);
        
        // [2] burns tribute to claim for recipient.
        seance.transferFrom(msg.sender, address(this), tribute);
        outcaster.outCast(tribute);

        // [3] transfers soul to the recipient
        soul.transfer(recipient, scarabs[id].amount);

        emit Saved(recipient, scarabs[id].amount);  

    }

    function claimScarabs(uint count) external {
        uint[] memory myScarabs = getScarabs();
        require(count <= 5, 'Cannot exceed 5 claims in one transaction.');

        // for loop: withdraws up to 5.
        for (uint i = 0; i < count; i++) {
            if (i < count) {
                withdrawTokens(myScarabs[i]);
                i ++;
                // skip to next iteration with continue
                continue;
            }

            if (i > count) {
                // exit loop with break: when amount limit reached
                break;
            }
        }
    }

    function getTribute(uint amount) public view returns (uint fee) {
        require(amount > 0, 'cannot have zero fee');
        return amount * tributeRate / 100;
    }
    
    function getDepositsByTokenAddress(address _token) view external returns (uint[] memory) { return depositsByTokenAddress[_token]; }
    function getDepositsByRecipient(address _recipient) view external returns (uint[] memory) { return depositsByRecipient[_recipient]; }
    function getScarabs() view public returns (uint[] memory) { return depositsByRecipient[msg.sender]; }
    function getTotalLockedBalance() view external returns (uint) { return soul.balanceOf(address(this)); }
    
    function enWei(uint amount) public pure returns (uint) { return amount * 1E18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1E18; }
}