// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
// import '@openzeppelin/contracts/access/Ownable.sol';
// import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import './SoulPower.sol';
import './SeanceCircle.sol';
import './interfaces/IMigrator.sol';

// the summoner of souls | ownership transferred to a governance smart contract 
// upon sufficient distribution + the community's desire to self-govern.

contract SoulSummoner is Ownable, ReentrancyGuard {

    // user info
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

    // pool info
    struct Pools {
        IERC20 lpToken;       // lp token ierc20 contract.
        uint allocPoint;      // allocation points assigned to this pool | SOULs to distribute per second.
        uint lastRewardTime;  // most recent UNIX timestamp during which SOULs distribution occurred in the pool.
        uint accSoulPerShare; // accumulated SOULs per share, times 1e12.
    }

    // soul power: our native utility token
    address private soulAddress;
    SoulPower public soul;
    
    // seance circle: our governance token
    address private seanceAddress;
    SeanceCircle public seance;

    address public team; // receives 1/8 soul supply
    address public dao; // recieves 1/8 soul supply

    // migrator contract | has lotsa power
    IMigrator public migrator;

    // blockchain variables accounting for share of overall emissions
    uint public totalWeight;
    uint public weight;

    // soul x day x this.chain
    uint public dailySoul; // = weight * 250K * 1e18;

    // soul x second x this.chain
    uint public soulPerSecond; // = dailySoul / 86400;

    // bonus muliplier for early soul summoners
    uint public bonusMultiplier = 1;

    // timestamp when soul rewards began (initialized)
    uint public startTime;

    // ttl allocation points | must be the sum of all allocation points
    uint public totalAllocPoint;

    // summoner initialized state.
    bool public isInitialized;

    Pools[] public poolInfo; // pool info
    mapping (uint => mapping (address => Users)) public userInfo; // staker data

    // prevents: early reward distribution
    modifier isSummoned {
        require(isInitialized, 'rewards have not yet begun');
        _;
    }

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);

    event Initialized(address team, address dao, address soul, address seance, uint totalAllocPoint, uint weight);
    event PoolAdded(uint pid, uint allocPoint, IERC20 lpToken, uint totalAllocPoint);
    event PoolSet(uint pid, uint allocPoint);

    event WeightUpdated(uint weight, uint totalWeight);
    event RewardsUpdated(uint dailySoul, uint soulPerSecond);
    event AccountsUpdated(address dao, address team);
    event TokensUpdated(address soul, address seance);

    // validates: pool exists
    modifier validatePoolByPid(uint pid) {
        require(pid < poolInfo.length, 'pool does not exist');
        _;
    }

    // validate: pool uniqueness to eliminate duplication risk (internal view)
    function checkPoolDuplicate(IERC20 _token) internal view {
        uint length = poolInfo.length;

        for (uint pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _token, 'duplicated pool');
        }
    }

    function initialize(
        address _soulAddress, 
        address _seanceAddress, 
        uint _totalWeight,
        uint _weight,
        uint _stakingAlloc 
       ) external onlyOwner {
        require(!isInitialized, 'already initialized');

        soulAddress = _soulAddress;
        seanceAddress = _seanceAddress;
        dao = msg.sender;
        team = msg.sender;

        startTime = block.timestamp;

        totalWeight = _totalWeight + _weight;
        weight = _weight;
        uint allocPoint = _stakingAlloc;

        soul  = SoulPower(soulAddress);
        seance = SeanceCircle(seanceAddress);

        updateRewards(weight, totalWeight); // updates dailySoul and soulPerSecond

        // staking pool
        poolInfo.push(Pools({
            lpToken: soul,
            allocPoint: allocPoint,
            lastRewardTime: startTime,
            accSoulPerShare: 0
        }));

        isInitialized = true; // triggers initialize state
        totalAllocPoint += allocPoint; // kickstarts total allocation

        emit Initialized(team, dao, soulAddress, seanceAddress, totalAllocPoint, weight);
    }

    function updateMultiplier(uint _bonusMultiplier) external onlyRole(maat) { // maat -- goddess of cosmic order  // todo: mirror soulPower logic
        bonusMultiplier = _bonusMultiplier;
    }

    function updateRewards(uint _weight, uint _totalWeight) internal {
        uint share = _weight / _totalWeight; // share of ttl emissions for chain (chain % ttl emissions)
        dailySoul = share * (250000 * 1e18); // dailySoul (for this.chain) = share (%) x 250K (soul emissions constant)
        soulPerSecond = dailySoul / 1 days; // updates: daily rewards expressed in seconds (1 days = 86,400 secs)

        emit RewardsUpdated(dailySoul, soulPerSecond);
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    // add: new pool (operator)
    function addPool(uint _allocPoint, IERC20 _lpToken, bool _withUpdate) 
        public isSummoned onlyRole(isis) { // isis: the soul summoning goddess whose power transcends them all
            checkPoolDuplicate(_lpToken);
            _addPool(_allocPoint, _lpToken, _withUpdate);
    }

    // add: new pool (internal)
    function _addPool(uint _allocPoint, IERC20 _lpToken, bool _withUpdate) internal {
        if (_withUpdate) { massUpdatePools(); }

        totalAllocPoint += _allocPoint;
        
        poolInfo.push(
        Pools({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: block.timestamp > startTime ? block.timestamp : startTime,
            accSoulPerShare: 0
        }));
        
        updateStakingPool();
        uint pid = poolInfo.length;

        emit PoolAdded(pid, _allocPoint, _lpToken, totalAllocPoint);
    }

    // set: allocation points (operator)
    function set(uint pid, uint allocPoint, bool withUpdate) 
        external isSummoned validatePoolByPid(pid) onlyRole(maat) { // maat -- goddess of cosmic order
                if (withUpdate) { massUpdatePools(); } // updates all pools
                
                uint prevAllocPoint = poolInfo[pid].allocPoint;
                poolInfo[pid].allocPoint = allocPoint;
                
                if (prevAllocPoint != allocPoint) {
                    totalAllocPoint = totalAllocPoint - prevAllocPoint + allocPoint;
                    
                    updateStakingPool(); // updates only selected pool
            }

        emit PoolSet(pid, allocPoint);
    }

    // update: weight (operator)
    function updateWeight(uint newWeight) external isSummoned onlyRole(maat) { // maat -- goddess of cosmic order
        require(weight != newWeight, 'must be new weight value');
        
        if (weight < newWeight) {           // if weight is gained
            uint gain = newWeight - weight; // calculates weight gained
            totalWeight += gain;            // increases totalWeight
        }
        
        if (weight > newWeight)  {          // if weight is lost
            uint loss = weight - newWeight; // calculates weight gained
            totalWeight -= loss;            // decreases totalWeight
        }

        weight = newWeight; // updates weight variable      
        
        updateRewards(weight, totalWeight);

        emit WeightUpdated(weight, totalWeight);
    }

    // update: staking pool (internal)
    function updateStakingPool() internal {
        uint length = poolInfo.length;
        uint points;
        
        for (uint pid = 1; pid < length; ++pid) { 
            points = points + poolInfo[pid].allocPoint; 
        }

        if (points != 0) {
            points = points / 3;
            totalAllocPoint = totalAllocPoint - poolInfo[0].allocPoint + points;
            poolInfo[0].allocPoint = points;
        }
    }

    // set: migrator contract (owner)
    function setMigrator(IMigrator _migrator) external isSummoned onlyOwner {
        migrator = _migrator;
    }

    // migrate: lp tokens to another contract (migrator)
    function migrate(uint pid) external isSummoned validatePoolByPid(pid) {
        require(address(migrator) != address(0), 'no migrator set');
        Pools storage pool = poolInfo[pid];
        IERC20 lpToken = pool.lpToken;

        uint bal = lpToken.balanceOf(address(this));
        lpToken.approve(address(migrator), bal);
        IERC20 _lpToken = migrator.migrate(lpToken);
        require(bal == _lpToken.balanceOf(address(this)), "migrate: insufficient balance");
        pool.lpToken = _lpToken;
    }

    // view: bonus multiplier (public)
    function getMultiplier(uint _from, uint _to) public view returns (uint) {
        return (_to - _from) * bonusMultiplier; // todo: minus parens
    }

    // view: pending soul rewards (external)
    function pendingSoul(uint pid, address _user) external view returns (uint) {
        Pools memory pool = poolInfo[pid];
        Users storage user = userInfo[pid][_user];

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
        for (uint pid = 0; pid < length; ++pid) { updatePool(pid); }
    }

    // update: rewards for a given pool id (public)
    function updatePool(uint pid) public validatePoolByPid(pid) {
        Pools storage pool = poolInfo[pid];

        if (block.timestamp <= pool.lastRewardTime) { return; }
        uint lpSupply = pool.lpToken.balanceOf(address(this));

        if (lpSupply == 0) { pool.lastRewardTime = block.timestamp; return; } // first staker in pool

        uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint soulReward = multiplier * soulPerSecond * pool.allocPoint / totalAllocPoint;
        
        uint divi = soulReward * 1e12 / 8e12; // 12.5% rewards x divi
        uint divis = divi * 2; // total divis
        uint shares = soulReward - divis; // net shares
        
        soul.mint(team, divi);
        soul.mint(dao, divi);
        soul.mint(address(seance), shares);

        pool.accSoulPerShare = pool.accSoulPerShare + soulReward * shares / lpSupply;
        pool.lastRewardTime = block.timestamp;
    }

    // deposit: lp tokens (lp owner)
    function deposit(uint pid, uint amount) external nonReentrant validatePoolByPid(pid) {
        require (pid != 0, 'deposit SOUL by staking');

        Pools memory pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];
        updatePool(pid);

        if (user.amount > 0) { // already deposited assets
            uint pending = (user.amount * pool.accSoulPerShare) / 1e12 - user.rewardDebt;
            if(pending > 0) { // sends pending rewards, if applicable
                safeSoulTransfer(msg.sender, pending);
            }
        }

        if (amount > 0) { // if adding more
            pool.lpToken.transferFrom(address(msg.sender), address(this), amount);
            user.amount = user.amount + amount;
        }

        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;
        emit Deposit(msg.sender, pid, amount);
    }

    // withdraw: lp tokens (external farmers)
    function withdraw(uint pid, uint amount) external nonReentrant validatePoolByPid(pid) {
        require (pid != 0, 'withdraw SOUL by unstaking');
        Pools memory pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];

        require(user.amount >= amount, 'withdraw not good');
        updatePool(pid);

        uint pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;

        if(pending > 0) { safeSoulTransfer(msg.sender, pending); }

        if(amount > 0) {
            user.amount = user.amount - amount;
            pool.lpToken.transfer(address(msg.sender), amount);
        }

        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;
        emit Withdraw(msg.sender, pid, amount);
    }


    // stake: soul into summoner (external)
    function enterStaking(uint _amount) external nonReentrant {
        Pools memory pool = poolInfo[0];
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

    // unstake: your soul (external staker)
    function leaveStaking(uint amount) external nonReentrant {
        Pools memory pool = poolInfo[0];
        Users storage user = userInfo[0][msg.sender];

        require(user.amount >= amount, "withdraw: not good");
        updatePool(0);

        uint pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;

        if(pending > 0) {
            safeSoulTransfer(msg.sender, pending);
        }

        if(amount > 0) {
            user.amount = user.amount - amount;
            pool.lpToken.transfer(address(msg.sender), amount);
        }

        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;

        seance.burn(msg.sender, amount);
        emit Withdraw(msg.sender, 0, amount);
    }
    
    // transfer: seance (internal)
    function safeSoulTransfer(address account, uint amount) internal {
        seance.safeSoulTransfer(account, amount);
    }


    // update accounts: dao and team addresses (owner)
    function updateAccounts(address _dao, address _team) external onlyOwner {
        require(dao != _dao, 'must be a new account');
        require(team != _team, 'must be a new account');

        dao = _dao;
        team = _team;

        emit AccountsUpdated(dao, team);
    }

    // update token addresses: soul and seance addresses (owner)
    function updateTokens(address _soul, address _seance) external onlyOwner {
        require(soul != IERC20(_soul), 'must be a new token address');
        require(seance != IERC20(_seance), 'must be a new token address');

        soul = SoulPower(_soul);
        seance = SeanceCircle(_seance);

        emit TokensUpdated(_soul, _seance);
    }
}
