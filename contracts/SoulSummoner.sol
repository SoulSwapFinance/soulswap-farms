// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import './libs/Operable.sol';
import './SoulPower.sol';
import './SeanceCircle.sol';
import './libs/IMigrator.sol';

// SoulSummoner is the master of Soul -- we all have some power over the summoner.

// Ownership transferred to a governance smart contract once SOUL is sufficiently
// distributed and the community can show to govern itself.

contract SoulSummoner is ReentrancyGuard, Ownable, Operable {

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
        IERC20 lpToken;       // Address of LP token contract.
        uint allocPoint;      // How many allocation points assigned to this pool. SOULs to distribute per second.
        uint lastRewardTime;  // Most recent UNIX timestamp that SOULs distribution occurs.
        uint accSoulPerShare; // Accumulated SOULs per share, times 1e12. See below.
    }

    //** ADDRESSES **//

    // SOUL POWER!
    address private soulAddress;
    SoulPower public soul;
    
    // SEANCE TOKEN!
    address private seanceAddress;
    SeanceCircle public seance;

    // Team: recieves 12.5% of SOUL rewards.
    address public team;

    // DAO: recieves 12.5% of SOUL rewards.
    address public dao;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigrator public migrator;

    // ** GLOBAL VARIABLES ** //
    uint public chainId;
    uint public totalChains;
    uint public totalPower;
    uint public power;

    // SOUL per DAY
    uint public dailySoul = 250000 * 1e18;

    // SOUL power created per second.
    uint public soulPerSecond = dailySoul / 86400;

    // Bonus muliplier for early soul summoners.
    uint public bonusMultiplier = 1;

    // The UNIX timestamp when SOUL mining starts.
    uint public startTime;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;

    // Indicates SoulSummoner contract has been initialized.
    bool public initialized;

    // ** POOL VARIABLES ** //

    // POOLS x POOL INFO.
    Pools[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping (uint => mapping (address => Users)) public userInfo;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);

    event Initialized(address team, address dev, address soul, address seance, uint chainId, uint power);

    event PoolAdded(uint pid, uint allocPoint, IERC20 lpToken, uint totalAllocPoint);
    event PoolSet(uint pid, uint allocPoint);

    event PowerUpdated(uint power, uint totalPower);
    event RewardsUpdated(uint dailySoul, uint soulPerSecond);

    modifier isNotInitialized() {
        require(!initialized, "has already begun");
        _;
    }

    modifier isInitialized() {
        require(initialized, "has not begun");
        _;
    }

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "pool does not exist");
        _;
    }

    // VALIDATION -- ELIMINATES POOL DUPLICATION RISK -- NONE
    function checkPoolDuplicate(IERC20 _token
    ) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _token, "add: existing pool");
        }
    }

    function initialize(
        address _soulAddress, 
        address _seanceAddress, 
        uint _chainId,
        uint _totalChains,
        uint _totalPower,
        uint _power) external isNotInitialized onlyOwner {
        soulAddress = _soulAddress;
        seanceAddress = _seanceAddress;
        dao = msg.sender;
        team = msg.sender;

        startTime = block.timestamp;

        chainId = _chainId;
        totalChains = _totalChains;
        totalPower = _totalPower + _power;
        power = _power;

        soul  = SoulPower(soulAddress);
        seance = SeanceCircle(seanceAddress);


        // staking pool
        poolInfo.push(Pools({
            lpToken: soul,
            allocPoint: 1000,
            lastRewardTime: startTime,
            accSoulPerShare: 0
        }));

        initialized = true;

        totalAllocPoint = 1000;
        totalChains ++;

        emit Initialized(team, dao, soulAddress, seanceAddress, chainId, power);
    }

    function updateMultiplier(uint _bonusMultiplier) external onlyOperator {
        bonusMultiplier = _bonusMultiplier;
    }

    function updateRewards(uint _power, uint _totalPower) internal {
        uint factor = _power / _totalPower;

        dailySoul = factor * (250000 * 1e18) / totalChains;
        soulPerSecond = dailySoul / 1 days;

        emit RewardsUpdated(dailySoul, soulPerSecond);
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    // ADD -- NEW LP POOL -- OPERATOR
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public isInitialized onlyOperator {
        checkPoolDuplicate(_lpToken);
        addPool(_allocPoint, _lpToken, _withUpdate);
    }

    // ADD -- NEW LP POOL -- INTERNAL
    function addPool(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) internal {
        if (_withUpdate) { massUpdatePools(); }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            Pools({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accSoulPerShare: 0
            })
        );
        
        updateStakingPool();
        uint _pid = poolInfo.length;

        emit PoolAdded(_pid, _allocPoint, _lpToken, totalAllocPoint);

    }

    // UPDATE -- ALLOCATION POINT -- OWNER
    function set(uint _pid, uint _allocPoint, bool _withUpdate) external isInitialized onlyOperator validatePoolByPid(_pid) {
        if (_withUpdate) { massUpdatePools(); }
        uint prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
            updateStakingPool();
       }

       emit PoolSet(_pid, _allocPoint);
    }

    // UPDATE -- POWER -- OWNER
    function updatePower(uint _power) external onlyOwner {
        uint prevTotalPower = totalPower - power;
        totalPower = prevTotalPower + _power;

        updateRewards(power, totalPower);
        emit PowerUpdated(power, totalPower);
    }

    // UPDATE -- STAKING POOL -- INTERNAL
    function updateStakingPool() internal {
        uint length = poolInfo.length;
        uint points = 0;
        for (uint pid = 1; pid < length; ++pid) {
            points = points + poolInfo[pid].allocPoint;
        }
        if (points != 0) {
            points = points / 3;
            totalAllocPoint = totalAllocPoint - poolInfo[0].allocPoint + points;
            poolInfo[0].allocPoint = points;
        }
    }

    // SET -- MIGRATOR CONTRACT -- OWNER
    function setMigrator(IMigrator _migrator) external onlyOwner {
        migrator = _migrator;
    }

    // MIGRATE -- LP TOKENS TO ANOTHER CONTRACT -- MIGRATOR
    function migrate(uint _pid) external validatePoolByPid(_pid) {
        require(address(migrator) != address(0), 'no migrator set');
        Pools storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint bal = lpToken.balanceOf(address(this));
        lpToken.approve(address(migrator), bal);
        IERC20 _lpToken = migrator.migrate(lpToken);
        require(bal == _lpToken.balanceOf(address(this)), "migrate: insufficient balance");
        pool.lpToken = _lpToken;
    }

    // VIEW -- BONUS MULTIPLIER -- PUBLIC
    function getMultiplier(uint _from, uint _to) public view returns (uint) {
        return (_to - _from) * bonusMultiplier; // todo: minus parens
    }

    // VIEW -- PENDING SOUL
    function pendingSoul(uint _pid, address _user) external view returns (uint) {
        Pools storage pool = poolInfo[_pid];
        Users storage user = userInfo[_pid][_user];
        uint accSoulPerShare = pool.accSoulPerShare;
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint soulReward = multiplier * soulPerSecond * pool.allocPoint / totalAllocPoint;
            accSoulPerShare = accSoulPerShare + soulReward * 1e12 / lpSupply;
        }

        return user.amount * accSoulPerShare / 1e12 - user.rewardDebt;
    }

    // UPDATE -- REWARD VARIABLES FOR ALL POOLS (HIGH GAS) -- PUBLIC
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // UPDATE -- REWARD VARIABLES (POOL) -- PUBLIC
    function updatePool(uint _pid) public validatePoolByPid(_pid) {
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
            multiplier * soulPerSecond * pool.allocPoint / totalAllocPoint;
        
        uint divi = soulReward * 1e12 / 8e12; // 1/8th rewards
        uint divis = divi * 2; // total divis
        uint shares = soulReward - divis; // net shares
        
        soul.mint(team, divi);
        soul.mint(dao, divi);
        
        soul.mint(address(seance), shares);

        pool.accSoulPerShare = pool.accSoulPerShare + soulReward * shares / lpSupply;

        pool.lastRewardTime = block.timestamp;
    }

    // DEPOSIT -- LP TOKENS -- LP OWNERS
    function deposit(uint _pid, uint _amount) external nonReentrant validatePoolByPid(_pid) {

        require (_pid != 0, 'deposit SOUL by staking');

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
    function withdraw(uint _pid, uint _amount) external nonReentrant validatePoolByPid(_pid) {

        require (_pid != 0, 'withdraw SOUL by unstaking');
        Pools storage pool = poolInfo[_pid];
        Users storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, 'withdraw not good');

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


    // STAKE -- SOUL TO SOUL SUMMONER -- PUBLIC SOUL HOLDERS
    function enterStaking(uint _amount) external nonReentrant {
        Pools storage pool = poolInfo[0];
        Users storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;
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

    // WITHDRAW -- SOUL powers from STAKING.
    function leaveStaking(uint _amount) external nonReentrant {
        Pools storage pool = poolInfo[0];
        Users storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;
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
    function safeSoulTransfer(address _to, uint _amount) internal {
        seance.safeSoulTransfer(_to, _amount);
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
    function newSoul(SoulPower _soul) external onlyOwner {
        require(soul != _soul, 'must be a new address');
        soul = _soul;
    }

    // UPDATE -- SEANCE ADDRESS -- OWNER
    function newSeance(SeanceCircle _seance) external onlyOwner {
        require(seance != _seance, 'must be a new address');
        seance = _seance;
    }

}
