// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract IsisProtocol is Ownable {

   address public ERC20Token;
   address public summonerPool;
   
   enum Functions { ERC, POOL }    
   uint256 private constant _TIMELOCK = 3600;     // 6H
   mapping(Functions => uint256) public timelock;

  // ensures: the lock delay has passed.
   modifier notLocked(Functions _fn) {
     require(timelock[_fn] != 0 && timelock[_fn] <= block.timestamp, "Function is timelocked");
     _;
   }
  
  // unlock: functions
  function unlockFunction(Functions _fn) public onlyOwner {
    timelock[_fn] = block.timestamp + _TIMELOCK;
  }
  
  // lock: functions
  function lockFunction(Functions _fn) public onlyOwner {
    timelock[_fn] = 0;
  }
    
  // create: Pool
  function setSummonerPool(address _pool) public onlyOwner notLocked(Functions.POOL) {
      summonerPool = _pool;
      timelock[Functions.POOL] = 0;
  }
    
}