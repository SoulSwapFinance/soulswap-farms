// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
pragma experimental ABIEncoderV2;
import './ERC20.sol';

contract Multicall {

    ERC20 public immutable wftm = ERC20(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    ERC20 public immutable fusd = ERC20(0xAd84341756Bf337f5a0164515b1f6F993D194E1f);

    address public ftmFusdPool = 0x11b5B41b55724427B44A8625AE14F24e0CaAD586;
    address public summoner;
    address private buns = msg.sender;

    bool isInitialized;
    event Initialized(address summoner);

    struct Call {
        address target;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function initialize(address _summoner) public {
        require(msg.sender == buns, 'only buns');
        require(!isInitialized, 'already initialized');

        summoner = _summoner;
        isInitialized = true;

        emit Initialized(summoner);
    }

    function aggregate(Call[] memory calls) public returns (uint256 blockNumber, bytes[] memory returnData) {
        blockNumber = block.number;
        returnData = new bytes[](calls.length);
        for(uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);
            require(success, "aggregate: call failed");
            returnData[i] = ret;
        }
    }

    function blockAndAggregate(Call[] memory calls) public returns (uint256 blockNumber, bytes32 blockHash, Result[] memory returnData) {
        (blockNumber, blockHash, returnData) = tryBlockAndAggregate(true, calls);
    }

    function tryAggregate(bool requireSuccess, Call[] memory calls) public returns (Result[] memory returnData) {
        returnData = new Result[](calls.length);
        for(uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);
            if (requireSuccess) { require(success, "aggregate: call failed"); }
            returnData[i] = Result(success, ret);
        }
    }

    function tryBlockAndAggregate(bool requireSuccess, Call[] memory calls) 
        public returns (uint256 blockNumber, bytes32 blockHash, Result[] memory returnData) {
            blockNumber = block.number;
            blockHash = blockhash(block.number);
            returnData = tryAggregate(requireSuccess, calls);
    }
    
    // helper functions
    function getEthBalance(address addr) public view returns (uint balance) {
        balance = addr.balance;
    }

    function getBlockNumber() public view returns (uint256 blockNumber) {
        blockNumber = block.number;
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

    function getTokenBalance(ERC20 token, address account) public view returns (uint balance) {
        balance = token.balanceOf(account);
    }

    // acquires sum of stableCoins in pool (e.g. fusd, usdc) and returns total value of pool wrt stableCoin
    function getDollarValue(ERC20 stableCoin, address pool) public view returns (uint value) {
        value = stableCoin.balanceOf(pool) * 2;
    }

    function getFtmValue(address pool) public view returns (uint value) {
        value = wftm.balanceOf(pool) * 2;
    }

    function getFusdValue(address pool) public view returns (uint value) {
        value = fusd.balanceOf(pool) * 2;
    }

    function getFtmFusdValue() public view returns (uint value) {
        value = fusd.balanceOf(ftmFusdPool) * 2;
    }

    function getValueLocked(ERC20 pool) public view returns (uint value) {
        uint lockedAmount = pool.balanceOf(summoner);
        uint fusdValue = getFusdValue(address(pool));      // gets value in FUSD ($)
        uint ftmValue = getFtmValue(address(pool));       // gets value in FTM
        uint ftmUsdValue = getFtmFusdValue(); // gets ftm USD($) value

        bool isFusdPool = fusdValue >= ftmValue;

        uint lpValue = isFusdPool        // checks if fusd pool
            ? fusdValue                 // if fusd pool --> get fusdValue
            : ftmValue * ftmUsdValue;                // if ftm pool --> get ftmValue
        
        value = lpValue * lockedAmount; // value ($) of each lp * amount locked
    }

    
}