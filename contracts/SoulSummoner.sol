// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './SoulPower.sol';
import './SeanceCircle.sol';
import './libs/IMigrator.sol';

// the summoner of souls | ownership transferred to a governance smart contract 
// upon sufficient distribution + the community's desire to self-govern.

contract SoulSummoner is Operable, ReentrancyGuard {

    // info of each user.
    struct Users {
        uint amount;     // ttl lp tokens user has provided
        uint rewardDebt; // reward debt (see below)
        //
        // we do some fancy math here. basically, any point in time, the amount of SOUL
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSoulPerShare) - user.rewardDebt
        //
        // the following occurs when anyone deposits or withdraws lp tokens to a pool:
        //   1. pool: `accSoulPerShare` and `lastRewardTime` get updated.
        //   2. user: receives pending reward.
        //   3. user: `amount` updates(+/-).
        //   4. user: `rewardDebt` updates (+/-).
    }

    // info of each pool.
    struct Pools {
        IERC20 lpToken;       // lp token ierc20 contract.
        uint allocPoint;      // allocation points assigned to this pool | SOULs to distribute per second.
        uint lastRewardTime;  // most recent UNIX timestamp during which SOULs distribution occurred in the pool.
        uint accSoulPerShare; // accumulated SOULs per share, times 1e12.
    }

    // SOUL POWER!
    address private soulAddress;
    SoulPower public soul;
    
    // SEANCE TOKEN!
    address private seanceAddress;
    SeanceCircle public seance;

    address public team; // receives 1/8 soul supply
    address public dao; // recieves 1/8 soul supply

    // migrator contract | has a lot of power.
    IMigrator public migrator;

    // ** GLOBAL VARIABLES ** //
    uint public chainId;
    uint public totalWeight;
    uint public weight;

    // SOUL per DAY
    uint public dailySoul; // = weight * 250K * 1e18;

    // SOUL / second.
    uint public soulPerSecond = 0; // = dailySoul / 86400;

    // bonus muliplier for early soul summoners.
    uint public bonusMultiplier = 1;

    // UNIX timestamp when SOUL mining starts.
    uint public startTime;

    // ttl allocation points | must be the sum of all allocation points.
    uint public totalAllocPoint;

    // summoner initialized state.
    bool public isInitialized;

    Pools[] public poolInfo; // pool info
    mapping (uint => mapping (address => Users)) public userInfo; // staker data

    modifier isSummoned {
        require(isInitialized, 'farming has not yet begun');
        _;
    }

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);

    event Initialized(address team, address dev, address soul, address seance, uint chainId, uint power);

    event PoolAdded(uint pid, uint allocPoint, IERC20 lpToken, uint totalAllocPoint);
    event PoolSet(uint pid, uint allocPoint);

    event WeightUpdated(uint weight, uint totalWeight);
    event RewardsUpdated(uint dailySoul, uint soulPerSecond);

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
        uint _totalWeight,
        uint _weight) external onlyOwner {
        require(!isInitialized, 'already initialized');

        soulAddress = _soulAddress;
        seanceAddress = _seanceAddress;
        dao = msg.sender;
        team = msg.sender;

        startTime = block.timestamp;

        chainId = _chainId;
        totalWeight = _totalWeight + _weight;
        weight = _weight;

        soul  = SoulPower(soulAddress);
        seance = SeanceCircle(seanceAddress);

        updateRewards(weight, totalWeight); // updates dailySoul and soulPerSecond

        // staking pool
        poolInfo.push(Pools({
            lpToken: soul,
            allocPoint: 1000,
            lastRewardTime: startTime,
            accSoulPerShare: 0
        }));

        isInitialized = true;
        totalAllocPoint = 1000;

        emit Initialized(team, dao, soulAddress, seanceAddress, chainId, weight);
    }

    function updateMultiplier(uint _bonusMultiplier) external onlyOperator {
        bonusMultiplier = _bonusMultiplier;
    }

    function updateRewards(uint _weight, uint _totalWeight) internal {
        uint share = _weight / _totalWeight; // share of ttl emissions for chain
        dailySoul = share * (250000 * 1e18); // updates daily rewards x share(%) of ttl emissions
        soulPerSecond = dailySoul / 1 days; // updates daily soul rewards / sec

        emit RewardsUpdated(dailySoul, soulPerSecond);
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    // ADD -- NEW LP POOL -- OPERATOR
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public isSummoned onlyOperator {
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

    // set the allocation points (operator)
    function set(uint _pid, uint _allocPoint, bool _withUpdate) external isSummoned validatePoolByPid(_pid) onlyOperator {
        if (_withUpdate) { massUpdatePools(); }
        uint prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
            updateStakingPool();
       }

       emit PoolSet(_pid, _allocPoint);
    }

    // increase weight (operator)
    function newWeight(uint _weight) external isSummoned onlyOperator {
        require(weight != _weight, 'must be new weight value');
        
        if (weight < _weight) { // if weight is gained
            uint gain = _weight - weight; // calculates weight gained
            totalWeight += gain; // increases totalWeight

            if (weight > _weight)  { // if weight is lost
                uint loss = weight - _weight; // calculates weight gained
                totalWeight -= loss; // decreases totalWeight
            }

            weight = _weight; // updates weight variable      
        }
        
        updateRewards(weight, totalWeight);
        emit WeightUpdated(weight, totalWeight);
    }

    // updates staking pool (internal)
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

    // sets migrator contract (owner)
    function setMigrator(IMigrator _migrator) external isSummoned onlyOwner {
        migrator = _migrator;
    }

    // migrates lp tokens to another contract (migrator)
    function migrate(uint _pid) external isSummoned validatePoolByPid(_pid) {
        require(address(migrator) != address(0), 'no migrator set');
        Pools storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint bal = lpToken.balanceOf(address(this));
        lpToken.approve(address(migrator), bal);
        IERC20 _lpToken = migrator.migrate(lpToken);
        require(bal == _lpToken.balanceOf(address(this)), "migrate: insufficient balance");
        pool.lpToken = _lpToken;
    }

    function getMultiplier(uint _from, uint _to) public view returns (uint) {
        return (_to - _from) * bonusMultiplier; // todo: minus parens
    }

    // external view for pendingSoul
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

    // update: rewards for all pools (public)
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // update: rewards for a given pool id (public)
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

    // deposit: lp tokens (lp owner)
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

    // withdraw: lp tokens (stakers)
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
