// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './libraries/SafeERC20.sol';
import './Outcaster.sol';

contract SoulScarab is Ownable {
    using SafeERC20 for IERC20;

    SeanceCircle public immutable seance = SeanceCircle(0x124B06C5ce47De7A6e9EFDA71a946717130079E6);
    SoulPower public immutable soul = SoulPower(0xe2fb177009FF39F52C0134E8007FA0e4BaAcBd07);
    Outcaster private immutable outcaster = Outcaster(0xFd63Bf84471Bc55DD9A83fdFA293CCBD27e1F4C8);
    
    struct Scarabs {
        address recipient;
        uint amount;
        uint tribute;
        uint unlockTimestamp;
        bool withdrawn;
    }
    
    uint public depositsCount;
    mapping (address => uint[]) public depositsByWithdrawer;
    mapping (uint => Scarabs) public lockedToken;
    mapping (address => uint) public walletBalance;
    
    address public manifestor;
    uint public tributeRate = 10 * 1E18; // 10%
    
    event Withdraw(address recipient, uint amount);
    event Lock(address token, uint amount, uint id);
    event FeeRateUpdated(uint feeRate);
    
    constructor() { manifestor = msg.sender; }
    
    function lockTokens(address _recipient, uint _amount, uint _unlockTimestamp) external returns (uint id) {
        require(_amount > 0, 'Insufficient Soul balance.');
        require(_unlockTimestamp < 10000000000, 'Unlock is not in second.');
        require(_unlockTimestamp > block.timestamp, 'Unlock is not in the future.');
        require(soul.allowance(msg.sender, address(this)) >= _amount, 'Approve tokens first.');

        // soul balance [before the deposit]
        uint beforeDeposit = soul.balanceOf(address(this));

        // transfers your soul into a Scarab
        soul.transferFrom(msg.sender, address(this), _amount);

        // soul balance [after the deposit]
        uint afterDeposit = soul.balanceOf(address(this));
        
        // safety precaution
        _amount = afterDeposit - beforeDeposit; 

        // calulates tribute amount
        uint _tribute = getTribute(_amount);
                
        walletBalance[msg.sender] = walletBalance[msg.sender] + _amount;
        
        id = ++depositsCount;
        lockedToken[id].recipient = _recipient;
        lockedToken[id].amount = _amount;
        lockedToken[id].tribute = _tribute;
        lockedToken[id].unlockTimestamp = _unlockTimestamp;
        lockedToken[id].withdrawn = false;
        
        depositsByWithdrawer[_recipient].push(id);

        emit Lock(address(soul), _amount, id);
        
        return id;
    }
        
    function withdrawTokens(uint id) external {
        require(block.timestamp >= lockedToken[id].unlockTimestamp, 'Tokens are still locked.');
        require(msg.sender == lockedToken[id].recipient, 'You are not the recipient.');
        require(lockedToken[id].withdrawn, 'Tokens are already withdrawn.');
        
        lockedToken[id].withdrawn = true;
        
        walletBalance[msg.sender] 
            = walletBalance[msg.sender] - lockedToken[id].amount;
        
        soul.transfer(msg.sender, lockedToken[id].amount);

        // acquires tribute amount
        uint tribute = getTribute(lockedToken[id].amount);
        
        // burns tribute to claim
        seance.transferFrom(msg.sender, address(outcaster), tribute);

        emit Withdraw(msg.sender, lockedToken[id].amount);  
    }
    
    // enables tranfer of manifestor status (useful for FE)
    function setManifestor(address _manifestor) external onlyOwner {
        manifestor = _manifestor;
    }

    // calculates the tribute for a given amount
    function getTribute(uint amount) public view returns (uint fee) {
        require(amount > 0, 'cannot have zero fee');
        return amount * tributeRate / 100;
    }
    
    function getDepositsByWithdrawer(address _recipient) external view returns (uint[] memory) {
        return depositsByWithdrawer[_recipient];
    }
    
    function getTotalLockedBalance() view external returns (uint) {
       return soul.balanceOf(address(this));
    }
}
