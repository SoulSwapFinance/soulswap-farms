// SPDX-License-Identifier: MIT

import './IMigrator.sol';

pragma solidity ^0.8.0;

interface ISummoner {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function enterStaking(uint256 _amount) external;

    function leaveStaking(uint256 _amount) external; 
    function setMigrator(IMigrator _migrator) external;

    function pendingSoul(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

}
