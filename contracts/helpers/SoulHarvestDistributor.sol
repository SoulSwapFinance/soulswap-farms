// SPDX-License-Identifier: MIT

import '../interfaces/ISummoner.sol';

pragma solidity >=0.8.0;

contract SoulHarvestDistributor {

    ISummoner public summoner = ISummoner(0xce6ccbB1EdAD497B4d53d829DF491aF70065AB5B);
    address public accountant = msg.sender;

    mapping (uint => mapping (address => Users)) public userInfo; // staker data


    // user info
    struct Users {
        uint amount;           // total tokens user has provided.
        uint rewardDebt;       // reward debt (see below).
        //   pending reward = (user.amount * pool.accSoulPerShare) - user.rewardDebt

        // the following occurs when a user +/- tokens to a pool:
        //   1. pool: `accSoulPerShare` and `lastRewardTime` update.
        //   2. user: receives pending reward.
        //   3. user: `amount` updates(+/-).
        //   4. user: `rewardDebt` updates (+/-).
    }

    event TransactionAdded(address indexed account, uint indexed pid, uint harvested);
    event DepositAdded(address indexed account, uint indexed pid, uint deposited, uint harvested);
    event WithdrawAdded(address indexed account, uint indexed pid, uint withdrawn, uint harvested);
    event HarvestAdded(address indexed account, uint indexed pid, uint harvested);
    event newAccountant(address accountant);
    
    function stakedAmount(uint pid) public view returns (uint bigStaked, uint staked) {
       (bigStaked,,,,,,) = summoner.userInfo(pid, msg.sender);
       staked = fromWei(bigStaked);

       return (bigStaked, staked);
    }

    function stakedAmount(uint pid, address account) public view returns (uint bigStaked, uint staked) {
        (bigStaked,,,,,,) = summoner.userInfo(pid, account);
        staked = fromWei(bigStaked);

        return (bigStaked, staked);

    }

    function rewardDebt(uint pid) public view returns (uint bigDebt, uint debt) {
       (,bigDebt,,,,,) = summoner.userInfo(pid, msg.sender);
        debt = fromWei(bigDebt);

        return (bigDebt, debt);    
    }

    function rewardDebt(uint pid, address account) public view returns (uint bigDebt, uint debt) {
       (,bigDebt,,,,,) = summoner.userInfo(pid, account);
       debt = fromWei(bigDebt);

        return (bigDebt, debt); 
    }

    function pendingRewards(uint pid) public view returns (uint bigPending, uint pending) {
       bigPending = summoner.pendingSoul(pid, msg.sender);
       pending = fromWei(bigPending);

       return (bigPending, pending);
    }

    function pendingRewards(uint pid, address account) public view returns (uint bigPending, uint pending) {
        bigPending = summoner.pendingSoul(pid, account);
        pending = fromWei(bigPending);

       return (bigPending, pending);
    }

    // update user's ledger with a reported transaction
    function addTransaction(bool isDeposit, uint pid, address account, uint amount, uint harvested) public {
        require(msg.sender == accountant, 'only the accountant may update ledger');
        
        // case: tokens deposited, else harvested only.
        isDeposit && amount > 0
            ? addDeposit(pid, account, amount, harvested)
            : addHarvest(pid, account, harvested);

        // case: tokens withdrawn, else harvested only. 
        !isDeposit && amount > 0
            ? addWithdrawal(pid, account, amount, harvested)
            : addHarvest(pid, account, harvested);
        
        emit TransactionAdded(account, pid, harvested);
    }

    // update user's balance with a reported deposit
    function addDeposit(uint pid, address account, uint deposited, uint harvested) public {
        require(msg.sender == accountant, 'only the accountant may update ledger');
        
        Users storage user = userInfo[pid][account];
        user.amount += deposited;

        emit DepositAdded(account, pid, deposited, harvested);
    }

    // update user's balance with a reported withdrawal
    function addWithdrawal(uint pid, address account, uint withdrawn, uint harvested) public {
        require(msg.sender == accountant, 'only the accountant may update ledger');
        
        Users storage user = userInfo[pid][account];
        user.amount += withdrawn;

        emit WithdrawAdded(account, pid, withdrawn, harvested);
    }

    // update user's balance with a manually-added deposit
    function addHarvest(uint pid, address account, uint harvested) public {
        require(msg.sender == accountant, 'only the accountant may update ledger');
        
        Users storage user = userInfo[pid][account];
        user.amount += harvested;

        emit HarvestAdded(account, pid, harvested);
    }

    function updateAccountant(address _accountant) public {
        require(msg.sender == accountant, 'only accountant may update');
        
        accountant = _accountant;

        emit newAccountant(_accountant);
    }

    function fromWei(uint bigAmount) public pure returns(uint amount) {
        return bigAmount / 1E18;
    }

    function toWei(uint amount) public pure returns(uint bigAmount) {
        return amount * 1E18;
    }
}
