// SPDX-License-Identifier: MIT

import './IMigrator.sol';

pragma solidity >=0.8.0;

interface ISummoner {
    function deposit(uint _pid, uint _amount) external;
    function withdraw(uint _pid, uint _amount) external;
    function enterStaking(uint _amount) external;

    function leaveStaking(uint _amount) external; 
    function setMigrator(IMigrator _migrator) external;

    function pendingSoul(uint _pid, address _user) external view returns (uint);
    function userInfo(uint _pid, address _user) 
        external view returns (
        uint amount,                // total tokens user has provided.
        uint rewardDebt,            // reward debt (see below).
        uint rewardDebtAtTime,      // the last time user stake.
        uint lastWithdrawTime,      // the last time a user withdrew at.
        uint firstDepositTime,      // the last time a user deposited at.
        uint timeDelta,             // time passed since withdrawals.
        uint lastDepositTime        // most recent deposit time.
        );
}
