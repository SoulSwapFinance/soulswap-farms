// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import './SoulToken.sol';
import './SpellBound.sol';
import './libs/IMigratorChef.sol';

// MasterChef is the master of Soul. She can make Soul and she is a fair lady.

// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SOUL is sufficiently
// distributed and the community can show to govern itself.

contract MasterChef is Ownable {

    // Info of each user.
    struct Users {
        uint amount;     // How many LP tokens the user has provided.
        uint rewardDebt; // Reward debt. See explanation below.
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
    struct Pools {
        IERC20 lpToken;          // Address of LP token contract.
        uint allocPoint;      // How many allocation points assigned to this pool. SOULs to distribute per second.
        uint lastRewardTime;  // Most recent UNIX timestamp that SOULs distribution occurs.
        uint accSoulPerShare; // Accumulated SOULs per share, times 1e12. See below.
    }

    //** ADDRESSES **//

    // SOUL TOKEN!
    address private soulAddress;
    SoulToken public soul;
    
    // SPELL TOKEN!
    address private spellAddress;
    SpellBound public spell;

    // Team: recieves 12.5% of SOUL rewards.
    address public team;

    // DAO: recieves 12.5% of SOUL rewards.
    address public dao;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    // ** GLOBAL VARIABLES ** //
    uint public chainId;
    uint public totalChains;
    uint public totalPower;
    uint public power;

    // SOUL per DAY
    uint public dailySoul = 250000 * 1e18;

    // SOUL tokens created per second.
    uint public soulPerSecond = dailySoul / 86400;

    // Bonus muliplier for early soul summoners.
    uint public BONUS_MULTIPLIER = 1;

    // The UNIX timestamp when SOUL mining starts.
    uint public startTime;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;

    // Indicates MasterChef contract has been initialized.
    bool public initialized;

    // ** POOL VARIABLES ** //

    // POOLS x POOL INFO.
    Pools[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping (uint => mapping (address => Users)) public userInfo;

    // stores an address for each creators
    mapping(address => bool) public creators;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);

    event Initialized(address team, address dev, address soul, address spell, uint chainId, uint power);

    event CreatorAdded(address indexed user);
    event CreatorRemoved(address indexed user);

    event PoolAdded(uint pid, uint allocPoint, IERC20 lpToken, uint totalAllocPoint);
    event PoolSet(uint pid, uint allocPoint);

    event PowerUpdated(uint power, uint totalPower);
    event RewardsUpdated(uint dailySoul, uint soulPerSecond);

    modifier onlyCreator() {
        require(isCreator(msg.sender), 'only minter allowed to add');
        _;
    }

    modifier isNotInitialized() {
        require(!initialized, "has already begun");
        _;
    }

    modifier isInitialized() {
        require(initialized, "has not begun");
        _;
    }

    function initialize(
        address _soulAddress, 
        address _spellAddress, 
        uint _chainId,
        uint _totalChains,
        uint _totalPower,
        uint _power) external isNotInitialized onlyOwner {
        creators[msg.sender] = true;
        soulAddress = _soulAddress;
        spellAddress = _spellAddress;
        dao = msg.sender;
        team = msg.sender;

        startTime = block.timestamp;

        chainId = _chainId;
        totalChains = _totalChains;
        totalPower = _totalPower + _power;
        power = _power;

        soul  = SoulToken(soulAddress);
        spell = SpellBound(spellAddress);

        initialized = true;

        totalAllocPoint = 1000;
        totalChains ++;

        emit Initialized(team, dao, soulAddress, spellAddress, chainId, power);
    }

    function isCreator(address _recipient) public view returns (bool) {
        return creators[_recipient];
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    // ADD -- NEW LP TOKEN POOL -- CREATOR
    function add(uint _allocPoint, IERC20 _lpToken, bool _withUpdate) external isInitialized onlyCreator {
        if (_withUpdate) massUpdatePools();
        uint lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(Pools({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accSoulPerShare: 0
        }));

        uint _pid = poolInfo.length;
        emit PoolAdded(_pid, _allocPoint, _lpToken, totalAllocPoint);
    }

    // UPDATE -- ALLOCATION POINT -- OWNER
    // Update the given pool's SOUL allocation point.
    function set(uint _pid, uint _allocPoint, bool _withUpdate) external isInitialized onlyCreator {
        uint prevAllocPoint = poolInfo[_pid].allocPoint;
        require(prevAllocPoint != _allocPoint, "set: assigning same alloc");
        if (_withUpdate) massUpdatePools();
        totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;

        emit PoolSet(_pid, _allocPoint);
    }

    // MIGRATE -- LP TOKENS TO ANOTHER CONTRACT -- MIGRATOR
    function migrate(uint _pid) external {
        require(address(migrator) != address(0), "migrate: no migrator set");
        Pools storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint bal = lpToken.balanceOf(address(this));
        lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: insufficient balance");
        pool.lpToken = newLpToken;
    }

    // VIEW -- BONUS MULTIPLIER -- PUBLIC
    function getMultiplier(uint _from, uint _to) public view returns (uint) {
        return _to - _from * BONUS_MULTIPLIER;
    }

    // VIEW -- PENDING SOUL
    function pendingSoul(uint _pid, address _user) external view returns (uint) {
        Pools storage pool = poolInfo[_pid];
        Users storage user = userInfo[_pid][_user];
        uint accSoulPerShare = pool.accSoulPerShare;
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint soulReward = (multiplier * soulPerSecond * pool.allocPoint) / totalAllocPoint;
            accSoulPerShare = accSoulPerShare + (soulReward * 1e12 / lpSupply);
        }
        return user.amount * accSoulPerShare / 1e12 - user.rewardDebt;
    }

    // UPDATE -- REWARD VARIABLES FOR ALL POOLS (HIGH GAS POSSIBLE) -- PUBLIC
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // UPDATE -- REWARD VARIABLES (POOL) -- PUBLIC
    function updatePool(uint _pid) public {
        Pools storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint soulReward = 
            (multiplier * soulPerSecond * pool.allocPoint) / totalAllocPoint;

        soul.mint(team, soulReward / 8); // 12.5% SOUL per second to team
        soul.mint(dao, soulReward / 8); // 12.5% SOUL per second to dao
        
        soul.mint(address(spell), soulReward);

        pool.accSoulPerShare = pool.accSoulPerShare + (soulReward * 1e12 / lpSupply);

        pool.lastRewardTime = block.timestamp;
    }

    // DEPOSIT -- LP TOKENS -- LP OWNERS
    function deposit(uint _pid, uint _amount) external {
        Pools storage pool = poolInfo[_pid];
        Users storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) { // already deposited assets
            uint pending = (user.amount * pool.accSoulPerShare) / 1e12 - user.rewardDebt;
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
    function withdraw(uint _pid, uint _amount) external {
        Pools storage pool = poolInfo[_pid];
        Users storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;
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

    // TRANSFER -- TRANSFERS SOUL -- INTERNAL
    // Just in case if rounding error causes pool to not have enough SOULs.
    function safeSoulTransfer(address _to, uint _amount) internal {
        uint256 soulBal = soul.balanceOf(address(this));
        if (_amount > soulBal) {
            soul.transfer(_to, soulBal);
        } else {
            soul.transfer(_to, _amount);
        }
    }

    // UPDATE -- REWARDS -- INTERNAL
    function updateRewards(uint _power, uint _totalPower) internal {
        uint factor = _power / _totalPower;

        dailySoul = factor * (250000 * 1e18) / totalChains;
        soulPerSecond = dailySoul / 1 days;

        emit RewardsUpdated(dailySoul, soulPerSecond);
    }

    // UPDATE -- POWER -- OWNER
    function updatePower(uint _power) external onlyOwner {
        uint prevTotalPower = totalPower - power;
        totalPower = prevTotalPower + _power;

        updateRewards(power, totalPower);
        emit PowerUpdated(power, totalPower);
    }

    // SET -- MIGRATOR CONTRACT -- OWNER
    function setMigrator(IMigratorChef _migrator) external onlyOwner {
        migrator = _migrator;
    }

    // UPDATE -- MULTIPLIER -- OWNER
    function updateMultiplier(uint multiplierNumber) external onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    // UPDATE -- DAO ADDRESS -- OWNER
    function newDAO(address _dao) external onlyOwner {
        require(dao != _dao, 'must be a new address');
        dao = _dao;
    }

    // UPDATE -- TEAM ADDRESS -- OWNER
    function newTeam(address _team) external onlyOwner {
        require(team != _team, 'must be a new address');
        team = _team;
    }

    // UPDATE -- SOUL ADDRESS -- OWNER
    function newSoul(SoulToken _soul) external onlyOwner {
        require(soul != _soul, 'must be a new address');
        soul = _soul;
    }

    // UPDATE -- SPELL ADDRESS -- OWNER
    function newSpell(SpellBound _spell) external onlyOwner {
        require(spell != _spell, 'must be a new address');
        spell = _spell;
    }

    function addCreator(address _recipient) external onlyOwner {
        require(!isCreator(_recipient), 
        'addToCreators: already added to creators');
        creators[_recipient] = true;

        emit CreatorAdded(_recipient);
    }

    function removeCreator(address _creator) external onlyOwner {
        require(isCreator(_creator), 'removeCreator: not a creator');
        creators[_creator] = false;
        
        emit CreatorRemoved(_creator);
    }
}
