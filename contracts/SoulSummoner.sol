// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './SoulPower.sol';
import './SeanceCircle.sol';
import './interfaces/IMigrator.sol';

// the summoner of souls | ownership transferred to a governance smart contract 
// upon sufficient distribution + the community's desire to self-govern.
