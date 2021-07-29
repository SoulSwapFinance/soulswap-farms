// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
contract Multicall {

    struct Call {
        address target;
        bytes callData;
    }
    function aggregate(Call[] memory calls) public returns (uint blockNumber, bytes[] memory returnData) {
        blockNumber = block.number;
        returnData = new bytes[](calls.length);
        for(uint i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);
            require(success);
            returnData[i] = ret;
        }
    }
    // helper functions
    function getEthBalance(address addr) public view returns (uint balance) {
        balance = addr.balance;
    }
    function getBlockHash(uint blockNumber) public view returns (bytes32 blockHash) {
        blockHash = blockhash(blockNumber);
    }
    function getLastBlockHash() public view returns (bytes32 blockHash) {
        blockHash = blockhash(block.number - 1);
    }
    function getCurrentBlockTimestamp() public view returns (uint timestamp) {
        timestamp = block.timestamp;
    }
    function getCurrentTime() public view returns (uint currentTime) {
        currentTime = block.timestamp;
    }

    function getNextDay() public view returns (uint nextDay) {
        nextDay = block.timestamp + 1 days;
    }

    function getFutureTime(uint _futureDays) public view returns (uint futureTime) {
        futureTime = block.timestamp + (_futureDays * 1 days);
    }

    function getTimespan(uint _startTime, uint _endTime) public pure returns (uint timespan) {
        require(_endTime > _startTime, 'the egg does not precede the chicken');
        timespan = _endTime - _startTime;
    }

    function getCurrentBlockDifficulty() public view returns (uint difficulty) {
        difficulty = block.difficulty;
    }
    function getCurrentBlockGasLimit() public view returns (uint gaslimit) {
        gaslimit = block.gaslimit;
    }
    function getCurrentBlockCoinbase() public view returns (address coinbase) {
        coinbase = block.coinbase;
    }
}
