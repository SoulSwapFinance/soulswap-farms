// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICalculator {
    function getTokenPrice(address tokenAddress) external view returns (uint tokenPrice);
    function getSoulPrice() external view returns (uint soulPrice);
    function getPoolPrice(address poolAddress) external view returns (uint poolPrice);
    function getPendingRewardsValue(uint pid, address userAddress) external view returns (uint pendingValue);
    function getNativePrice() external view returns (uint nativePrice);
    function getPooledValue(uint pid, address lpAddress) external view returns (uint value);
}