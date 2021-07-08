// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';

import "./SoulToken.sol";
import "./SeanceCircle.sol";

interface IMigratorChef {
    // Perform LP token migration from legacy swap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.

    function migrate(IERC20 token) external returns (IERC20);
}

// MasterChef is the master of Soul. She can make Soul and she is a fair lady.

// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SOUL is sufficiently
// distributed and the community can show to govern itself.

contract MasterChef is Ownable {

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SOUL
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSoulPerShare) - user.rewardDebt

        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSoulPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to their address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;          // Address of LP token contract.
        uint256 allocPoint;      // How many allocation points assigned to this pool. SOULs to distribute per second.
        uint256 lastRewardTime;  // Most recent UNIX timestamp that SOULs distribution occurs.
        uint256 accSoulPerShare; // Accumulated SOULs per share, times 1e12. See below.
    }

    //** ADDRESSES **//

    // The SOUL TOKEN!
    SoulToken public soul;
    // The SEANCE TOKEN!
    SeanceCircle public seance;
    // Team address, which recieves 12.5% of SOUL rewards.
    address public team = msg.sender;
    // DAO address, which recieves 12.5% of SOUL rewards.
    address public dao = msg.sender;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;


    // ** GLOBAL VARIABLES ** //

    // Blockchains containing MasterChef contract
    uint256 public chains = 1;
    // SOUL per DAY
    uint256 public dailySoul = 250000 * 1e18; 
    // SOUL tokens created per second.
    uint256 public soulPerSecond = dailySoul / 86400;
    // Bonus muliplier for early soul summoners.
    uint256 public BONUS_MULTIPLIER = 1;
    // The UNIX timestamp when SOUL mining starts.
    uint256 public startTime = block.timestamp;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // ** POOL VARIABLES ** //

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        SoulToken _soul,
        SeanceCircle _seance
    ) {
        soul = _soul;
        seance = _seance;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _soul,
            allocPoint: 1000,
            lastRewardTime: startTime,
            accSoulPerShare: 0
        }));

        totalAllocPoint = 1000;
    }

    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function updateRewards() internal {
        dailySoul = (250000 * 1e18) / chains;
        soulPerSecond = dailySoul / 86400;
    }

    function updateChains(uint256 _chains) external onlyOwner {
        require(_chains != 0, 'chain cannot be zero');
        chains = _chains;
        updateRewards();
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // ADD -- NEW LP TOKEN POOL -- OWNER
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) external {
        require(msg.sender == owner() || msg.sender == dao, 'add: must be owner or dao');
        if (_withUpdate) massUpdatePools();
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accSoulPerShare: 0
        }));
        updateStakingPool();
    }

    // UPDATE -- ALLOCATION POINT -- OWNER
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external {
        require(msg.sender == owner() || msg.sender == dao, 'set: must be owner or dao');
        if (_withUpdate) massUpdatePools();
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
            updateStakingPool();
        }
    }

    // UPDATE -- STAKING POOL -- INTERNAL
    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points + poolInfo[pid].allocPoint;
        }
        if (points != 0) {
            points = points / 3;
            totalAllocPoint = totalAllocPoint - poolInfo[0].allocPoint + points;
            poolInfo[0].allocPoint = points;
        }
    }

    // SET -- MIGRATOR CONTRACT -- OWNER
    function setMigrator(IMigratorChef _migrator) external onlyOwner {
        migrator = _migrator;
    }

    // MIGRATE -- LP TOKENS TO ANOTHER CONTRACT -- MIGRATOR
    function migrate(uint256 _pid) external {
        require(address(migrator) != address(0), "migrate: no migrator set");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: insufficient balance");
        pool.lpToken = newLpToken;
    }

    // VIEW -- BONUS MULTIPLIER -- PUBLIC
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to - _from * BONUS_MULTIPLIER;
    }

    // VIEW -- PENDING SOUL
    function pendingSoul(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSoulPerShare = pool.accSoulPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 soulReward = (multiplier * soulPerSecond * pool.allocPoint) / totalAllocPoint;
            accSoulPerShare = accSoulPerShare + (soulReward * 1e12 / lpSupply);
        }
        return user.amount * accSoulPerShare / 1e12 - user.rewardDebt;
    }

    // UPDATE -- REWARD VARIABLES FOR ALL POOLS (HIGH GAS POSSIBLE) -- PUBLIC
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // UPDATE -- REWARD VARIABLES (POOL) -- PUBLIC
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 soulReward = 
            (multiplier * soulPerSecond * pool.allocPoint) / totalAllocPoint;

        soul.mint(team, soulReward / 8); // 12.5% SOUL per second to team
        soul.mint(dao, soulReward / 8); // 12.5% SOUL per second to dao
        
        soul.mint(address(seance), soulReward);

        pool.accSoulPerShare = pool.accSoulPerShare + (soulReward * 1e12 / lpSupply);

        pool.lastRewardTime = block.timestamp;
    }

    // DEPOSIT -- LP TOKENS -- LP OWNERS
    function deposit(uint256 _pid, uint256 _amount) external {

        require (_pid != 0, 'deposit SOUL by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) { // already deposited assets
            uint256 pending = (user.amount * pool.accSoulPerShare) / 1e12 - user.rewardDebt;
            if(pending > 0) { // sends pending rewards, if applicable
                safeSoulTransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) { // if adding more
            pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount + _amount;
        }
        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // WITHDRAW -- LP TOKENS -- STAKERS
    function withdraw(uint256 _pid, uint256 _amount) external {

        require (_pid != 0, 'withdraw SOUL by unstaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;
        if(pending > 0) {
            safeSoulTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.transfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // STAKE -- SOUL TO MASTERCHEF -- PUBLIC SOUL HOLDERS
    function enterStaking(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount * pool.accSoulPerShare/ 1e12 - user.rewardDebt;
            if(pending > 0) {
                safeSoulTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount + _amount;
        }
        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;

        seance.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // WITHDRAW -- SOUL tokens from STAKING.
    function leaveStaking(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;
        if(pending > 0) {
            safeSoulTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.transfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;

        seance.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // TRANSFER -- TRANSFERS SEANCE -- INTERNAL
    function safeSoulTransfer(address _to, uint256 _amount) internal {
        seance.safeSoulTransfer(_to, _amount);
    }

    // UPDATE -- TREASURY ADDRESS -- TREASURY || TEAM
    function newDAO(address _dao) external {
        require(msg.sender == dao || msg.sender == owner(), "newDAO: must be dao or owner");
        dao = _dao;
    }

    // UPDATE -- ADMIN ADDRESS -- ADMIN
    function newTeam(address _team) external {
        require(msg.sender == team || msg.sender == owner(), "newTeam: must be team or owner");
        team = _team;
    }
}
