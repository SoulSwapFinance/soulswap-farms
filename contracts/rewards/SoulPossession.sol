// SPDX-License-Identifier: MIT

//// @title SoulPossession.sol
/// @author Buns Enchantress
/// @notice Contract that controls the farming pools and enforces congruence.
/// @dev Ensure the contract consolidates power to initialize DAO-ification.

/* 

NOTABLE FEATURES & ENCHANCEMENTS

    SUMMARY: Isolated Farming Pools that enable the localization of rewards mechanism via a universal controller.
    This (Activates) Protocol Management (x) Leveraging Decentralized (Control), which helps our protocol keeps up 
    with new defi-farming techniques.

    • Single Source of Truth | Consolidates: the Protocol, Pools, and Power.

        1. Protocol Management
            • Rewards Allocation via AURA Transmutation
            • Gauge-esque Rewards
                - Use voting power to allocate towards multiplier on allocation.

        2. Pools Management
            • Creation of New Pools ("Farms")
            • Rewards Allocation (Control)
            • Key Function Calls
        
        3. Powered by Possession
            • Embedded AURA Allocation Visibility
            • "AURA-Empowered Emissions"

    • Key Benefits | Clarifies, Controls, Consolidates

        1. Clarifies
            • The utility of SOUL and power of one's AURA.
            • The voting power a user has at any given moment.

        2. Controls
            • Farming Allocation: this prevent over or under allocation.
            • Eliminates: Migrator Functionality.
            • Flexible Rewards Expression
                - For example, use rewards to auto-reinvest.

        3. Consolidates
            • Key Protocol Metrics: TVL, APR, Ownership, Generated Revenue.
            • Key User Metrics: voting power, total pending rewards, AURA allocation.
            • Strategies in effect, profitability of each component.
            • Updates: Alerts Upcoming Changes
                - New Integrated Farms: alerts users of new farms.
                - Farm Removal: alerts users when the farm is near expiration or termination.
                - Allocation Deltas: alert users to provides notification of a substantial change in allocation.
                - @dev consider using events + event listener for off-chain, UI notification system.
    
    • Examples | Farming Pools Smart Contracts
        1. Autocompounding Vault
            • Re-invests Harvests
        2. Rewards Variants
            • Rewards Vested Over Time
            • Time-Locked Rewards
            • Fees + Redistribution
        3. Early Withdrawal Fees
        4. Bonding Mechanisms (with voting power)
        5. Dual-Rewards // Rewards Fusion

*/

pragma solidity =0.8.0;

import '../libraries/ERC20.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/security/Pausable.sol';

contract SoulPossession is AccessControl, Pausable, ReentrancyGuard {

    // KEY ADDRESSES //

    // soul power: our native utility token.
    IERC20 public immutable SOUL = IERC20(0xe2fb177009FF39F52C0134E8007FA0e4BaAcBd07);
    // seance circle: our receipt token.
    IERC20 public immutable SEANCE = IERC20(0x124B06C5ce47De7A6e9EFDA71a946717130079E6);
    // team and dao: each receive 12.5% overall emissions.
    address public team = 0xd0744f7F9f65db946860B974966f83688D4f4630;
    address public dao = 0x1C63C726926197BD3CB75d86bCFB1DaeBcD87250;
    address public supreme = 0x81Dd37687c74Df8F957a370A9A4435D873F5e5A9;

    // KEY STRUCTS: MEMBERS + FARMERS + FARMS //

    // Member-Level Details (Member)
    struct Members {
        uint power;                  // total voting power a user holds (aka AURA).
        uint level;                  // corresponding AURA level (?)
        uint allocated;              // voting power allocated to a farm.
        uint claimed;                // total claimed by a user.
        uint lastTimeClaimed;        // most recent time a user claimed.
        uint lastTimeAllocated;      // most recent time user allocated power to a farm.

        //  pending reward = (user.amount * pool.accSoulPerShare) - user.rewardDebt

        // the following occurs when a user +/- to a pool (where applicable):
        //   1. members: `lastTimeClaimed` and/or `lastTimeAllocated` is updated.
        //   2. members: `power` and `level` are updated (if applicable).
        //   3. members: `allocated` and `claimed` update (+/-).
    }

    // Farmer-Level Details (Farm-Member) //
    struct Farmers {
        uint amount;           // total tokens farmer has deposited.
        uint rewardDebt;       // reward debt (see below).
        uint rewardDebtAtTime; // the last time user stake.
        uint lastWithdrawTime; // the last time a user withdrew at.
        uint firstDepositTime; // the last time a user deposited at.
        uint timeDelta;        // time passed since withdrawals.
        uint lastDepositTime;  // most recent deposit time.

        //  pending reward = (user.amount * pool.accSoulPerShare) - user.rewardDebt

        // the following occurs when a farmer +/- to a pool:
        //   1. pool: `accSoulPerShare` and `lastRewardTime` update.
        //   2. farmer: receives pending reward.
        //   3. farmer: `amount` updates(+/-).
        //   4. farmer: `rewardDebt` updates (+/-).
    }

    // Farm-Level Details
    struct Pools {
        IERC20 lpToken;       // lp token ierc20 contract.
        uint allocPoint;      // allocation points assigned to this pool | SOULs to distribute per second.
        uint lastRewardTime;  // most recent UNIX timestamp during which SOULs distribution occurred in the pool.
        uint accSoulPerShare; // accumulated SOULs per share, times 1e12.
    }



}