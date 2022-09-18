// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '../libraries/SafeERC20.sol';
import '../interfaces/IToken.sol';

// manifestor of new souls | ownership transferred to a governance smart contract 
// upon sufficient distribution + the community's desire to self-govern.

contract MockSoulManifester is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // user info
    struct Users {
        uint amount;            // deposited amount.
        uint rewardDebt;        // reward debt (see: pendingSoul).
        uint withdrawalTime;    // last withdrawal time.
        uint depositTime;       // first deposit time.
        uint timeDelta;         // seconds accounted for in fee calculation.
        uint deltaDays;         // days accounted for in fee calculation

        // the following occurs when a user +/- tokens to a pool:
        //   1. pool: `accSoulPerShare` and `lastRewardTime` update.
        //   2. user: receives pending reward.
        //   3. user: `amount` updates(+/-).
        //   4. user: `rewardDebt` updates (+/-).
    }

    // pool info
    struct Pools {
        IERC20 lpToken;       // lp token contract.
        uint allocPoint;      // allocation points, which determines SOUL distribution per second.
        uint lastRewardTime;  // latest SOUL distribution in the pool.
        uint accSoulPerShare; // accumulated SOUL per share (times 1e12).
        uint feeDays;         // days during which a fee applies (aka startRate or feeDuration).
    }

    // soul power: our native utility token
    address private soulAddress;
    IToken public soul;
    
    // seance circle: our governance token
    address private seanceAddress;
    IToken public seance;

    address public team;        // receives 1/8 supply
    address public dao;         // recieves 1/8 supply

    // rewarder variables: used to calculate share of overall emissions.
    uint public totalWeight;
    uint public weight;

    // global daily SOUL
    uint public immutable globalDailySoul = 250_000;

    // local daily SOUL
    uint public dailySoul; // = weight * globalDailySoul * 1e18;
    // rewards per second for this rewarder
    uint public soulPerSecond; // = dailySoul / 86400;

    // marks the beginning of soul rewards.
    uint public startTime;

    // total allocation points: must be the sum of all allocation points
    uint public totalAllocPoint;

    // bonus muliplier
    uint public immutable bonusMultiplier = 1;

    // decay rate on withdrawal fee of 1%.
    uint public immutable dailyDecay = enWei(1);
    
    // limits the maximum days to wait for a fee-less withdrawal.
    uint public immutable maxFeeDays = enWei(100);

    // initialization state
    bool public isInitialized;
    
    // emergency state
    bool public isEmergency;

    // activation state
    bool public isActivated;

    // pool info
    Pools[] public poolInfo;

    // user info
    mapping (uint => mapping (address => Users)) public userInfo;

    // divine roles
    bytes32 public isis; // soul summoning goddess of magic
    bytes32 public maat; // goddess of cosmic order

    // restricts: function to the council of the role passed as an object to obey (role)
    modifier obey(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    // controls: emergencyWithdrawals.
    modifier emergencyActive {
        require(isEmergency, 'emergency mode is not active.');
        _;
    }

    // proxy for pausing contract.
    modifier isActive {
        require(isInitialized, 'rewards have not yet begun.');
        require(isActivated, 'contract is currently paused');
        _;
    }

    // validates: pool exists
    modifier validatePoolByPid(uint pid) {
        require(pid < poolInfo.length, 'pool does not exist');
        _;
    }

    /*/ events /*/
    event Deposit(address indexed user, uint indexed pid, uint amount, uint timestamp);
    event Withdraw(address indexed user, uint indexed pid, uint amount, uint feeAmount, uint timeStamp);
    event Initialized(address soulAddress, address seanceAddress, uint weight);
    event PoolAdded(uint pid, uint allocPoint, IERC20 lpToken, uint totalAllocPoint);
    event PoolSet(uint pid, uint allocPoint);
    event WeightUpdated(uint weight, uint totalWeight);
    event RewardsUpdated(uint dailySoul, uint soulPerSecond);
    event FeeDaysUpdated(uint pid, uint feeDays);
    event AccountsUpdated(address dao, address team);
    event TokensUpdated(address soul, address seance);
    event DepositRevised(uint pid, address account, uint timestamp);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);

    // channels the power of isis & ma'at
    constructor() {
        address supreme = msg.sender;
        team = supreme;
        dao = supreme;

        isis = keccak256("isis"); // goddess of magic who creates pools
        maat = keccak256("maat"); // goddess of cosmic order who allocates emissions

        _divinationCeremony(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, supreme);
        _divinationCeremony(isis, isis, supreme); // isis role created -- supreme divined admin
        _divinationCeremony(maat, isis, supreme); // maat role created -- isis divined admin
    } 

    function _divinationCeremony(bytes32 _role, bytes32 _adminRole, address _account) internal returns (bool) {
            _setupRole(_role, _account);
            _setRoleAdmin(_role, _adminRole);
        return true;
    }

    // validates: pool uniqueness to eliminate duplication risk (internal view)
    function checkPoolDuplicate(IERC20 _token) internal view {
        uint length = poolInfo.length;

        for (uint pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _token, 'duplicated pool');
        }
    }

    // activates: rewards (isis)
    function initialize(address _soulAddress, address _seanceAddress, uint _weight) external obey(isis) {
        // checks: rewards have not already begun
        require(!isInitialized, 'rewards have already begun');

        // sets: times & weights
        startTime = block.timestamp;
        totalWeight = 1_000;
        weight = _weight;

        // sets: tokens
        soulAddress = _soulAddress;
        seanceAddress = _seanceAddress;
        soul  = IToken(_soulAddress);
        seance = IToken(_seanceAddress);

        // updates: dailySoul and soulPerSecond
        updateRewards(weight, totalWeight); 

        // adds: staking pool (allocation: 1,000 & withdrawFee: 0).
        poolInfo.push(Pools({
            lpToken: IERC20(_soulAddress),
            allocPoint: 1_000,
            lastRewardTime: startTime,
            accSoulPerShare: 0,
            feeDays: 0
        }));
        
        // triggers: initialization
        isInitialized = true;

        // sets: total allocation point.
        totalAllocPoint += 1_000;

        emit Initialized(_soulAddress, _seanceAddress, _weight);
    }

    // enables: panic button (ma'at)
    function toggleEmergency(bool enabled) external obey(maat) {
        isEmergency = enabled;
    }

    // toggles: pause state (isis)
    function toggleActive(bool enabled) external obey(isis) {
        isActivated = enabled;
    }

    // returns: amount of pools
    function poolLength() external view returns (uint) { return poolInfo.length; }

    // add: new pool created by the soul summoning goddess whose power transcends all (isis)
    function addPool(uint _allocPoint, IERC20 _lpToken, bool _withUpdate, uint _feeDays) public isActive obey(isis) { 
            checkPoolDuplicate(_lpToken);

            _addPool(_allocPoint, _lpToken, _withUpdate, _feeDays);
    }

    // add: pool
    function _addPool(uint _allocPoint, IERC20 _lpToken, bool _withUpdate, uint _feeDays) internal {
        if (_withUpdate) { massUpdatePools(); }

        totalAllocPoint += _allocPoint;

        poolInfo.push(
        Pools({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: block.timestamp > startTime ? block.timestamp : startTime,
            accSoulPerShare: 0,
            feeDays: enWei(_feeDays)
        }));
        
        updateStakingPool();
        uint pid = poolInfo.length;

        emit PoolAdded(pid, _allocPoint, _lpToken, totalAllocPoint);
    }

    // set: allocation points (ma'at)
    function set(uint pid, uint allocPoint, bool withUpdate) external isActive validatePoolByPid(pid) obey(maat) {
            // [if] withUpdate, [then] execute mass pool update.
            if (withUpdate) { massUpdatePools(); }
            
            // gets: previous allocation point & sets new allocation point
            uint prevAllocPoint = poolInfo[pid].allocPoint;
            poolInfo[pid].allocPoint = allocPoint;
            
            if (prevAllocPoint != allocPoint) {
                totalAllocPoint = totalAllocPoint - prevAllocPoint + allocPoint;
                
                updateStakingPool(); // updates selected pool (only)
        }

        emit PoolSet(pid, allocPoint);
    }

    // view: user delta is the time since user either last withdrew OR first deposited.
	function userDelta(uint pid, address _user) public view returns (uint delta) {
        // grabs the stored user data for the pool
        Users memory user = userInfo[pid][_user];

        // if user has never withdrawn
        user.withdrawalTime == 0 
            // then use the time since their first deposit
            ? delta = block.timestamp - user.depositTime
            // else, use the time since the last withdrawal
            : delta = block.timestamp - user.withdrawalTime;

        return delta;
	}

    // view: user delta is the time since user either last withdrew OR first deposited.
	function userDelta(uint pid) public view returns (uint delta) {
        // grabs the stored user data for the pool
        Users memory user = userInfo[pid][msg.sender];

        // if user has never withdrawn
        user.withdrawalTime == 0 
            // then use the time since their first deposit
            ? delta = block.timestamp - user.depositTime
            // else, use the time since the last withdrawal
            : delta = block.timestamp - user.withdrawalTime;

        return delta;  
	}

    // returns: multiplier during a period.
    function getMultiplier(uint from, uint to) public pure returns (uint) {
        return (to - from) * bonusMultiplier;
    }

    // gets: days based off a given timeDelta (seconds).
    function getDeltaDays(uint timeDelta) public pure returns (uint deltaDays) {
        deltaDays = timeDelta < 1 days ? 0 : timeDelta / 1 days;
        return deltaDays;     
    }

    // returns: fee rate for a given pid and timeDelta.
    function getFeeRate(uint pid, uint deltaDays) public view returns (uint feeRate) {
        // calculates: rateDecayed (converts to wei).
        uint rateDecayed = enWei(deltaDays);

        // gets: info & feeDays (pool)
        Pools memory pool = poolInfo[pid];
        uint feeDays = pool.feeDays; 

        // [if] more time has elapsed than wait period
        if (rateDecayed >= feeDays) {
            // [then] set feeRate to 0.
            feeRate = 0;
        } else { // [else] reduce feeDays by the rateDecayed.
            feeRate = feeDays - rateDecayed;
        }

        return feeRate;
    }

    // returns: feeAmount and with withdrawableAmount for a given pid and amount
    function getWithdrawable(uint pid, uint deltaDays, uint amount) public view returns (uint _feeAmount, uint _withdrawable) {
        // gets: feeRate
        uint feeRate = fromWei(getFeeRate(pid, deltaDays));
        // gets: feeAmount
        uint feeAmount = (amount * feeRate) / 100;
        // calculates: withdrawable amount
        uint withdrawable = amount - feeAmount;

        return (feeAmount, withdrawable);
    }

    // view: pending soul rewards
    function pendingSoul(uint pid, address account) public view returns (uint pendingAmount) {
        // gets: pool and user data
        Pools memory pool = poolInfo[pid];
        Users memory user = userInfo[pid][account];

        // gets: `accSoulPerShare` & `lpSupply` (pool)
        uint accSoulPerShare = pool.accSoulPerShare;
        uint lpSupply = pool.lpToken.balanceOf(address(this));

        // [if] holds deposits & rewards issued at least once (pool)
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            // gets: multiplier from the time since now and last time rewards issued (pool)
            uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            // get: reward as the product of the elapsed emissions and the share of soul rewards (pool)
            uint soulReward = multiplier * soulPerSecond * pool.allocPoint / totalAllocPoint;
            // adds: product of soulReward and 1e12
            accSoulPerShare += soulReward * 1e12 / lpSupply;
        }
        // returns: rewardShare for user minus the amount paid out (user)
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

        // [if] first staker in pool, [then] set lastRewardTime to meow.
        if (lpSupply == 0) { pool.lastRewardTime = block.timestamp; return; }

        // gets: multiplier from time elasped since pool began issuing rewards.
        uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint soulReward = multiplier * soulPerSecond * pool.allocPoint / totalAllocPoint;
        // gets: divi
        uint divi = soulReward * 1e12 / 8e12;   // 12.5% rewards
        
        soul.mint(team, divi);
        soul.mint(dao, divi);
        soul.mint(address(seance), soulReward); // prevents reward errors

        pool.accSoulPerShare = pool.accSoulPerShare + (soulReward * 1e12 / lpSupply);
        pool.lastRewardTime = block.timestamp;
    }

    // harvests: pending rewards for a given pid.
    function harvest(uint pid) public {
        if (pid == 0) { enterStaking(0); }
        else { deposit(pid, 0); }
    }
    
    // harvest: all pools in a single transaction.
    function harvestAll(uint[] calldata _pids) public {
        for (uint i = 0; i < _pids.length; ++i) {
            harvest(_pids[i]);
        }
    }

    // deposit: lp tokens (lp owner)
    function deposit(uint pid, uint amount) public nonReentrant isActive validatePoolByPid(pid) {
        require (pid != 0, 'deposit SOUL by staking (enterStaking)');
        
        // gets: stored data for pool and user.
        Pools storage pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];

        updatePool(pid);

        // [if] already deposited (user)
        if (user.amount > 0) {
            // [then] gets: pendingRewards using pendingSoul (pid, user).
            uint pendingRewards = pendingSoul(pid, msg.sender);
            // [if] rewards pending, then transfer to user.
            if(pendingRewards > 0) { 
                safeSoulTransfer(msg.sender, pendingRewards);
            }
        }

        // [if] depositing more
        if (amount > 0) {
            // [then] transfer lpToken from user to contract
            pool.lpToken.transferFrom(address(msg.sender), address(this), amount);
            // [then] increment deposit amount (user).
            user.amount += amount;
        }

        // updates: reward debt (user).
        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;

        // [if] first time depositing (user)
        if (user.depositTime == 0) {
            // [then] update depositTime
            user.depositTime = block.timestamp;
        }
        
        emit Deposit(msg.sender, pid, amount, block.timestamp);
    }

    // withdraw: lp tokens (external farmers)
    function withdraw(uint pid, uint amount) external nonReentrant isActive validatePoolByPid(pid) {
        require (pid != 0, 'withdraw SOUL by unstaking (leaveStaking)');
        require(amount > 0, 'cannot withdraw zero');

        Pools storage pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];

        require(user.amount >= amount, 'withdrawal exceeds deposit');
        updatePool(pid);

        // gets: pending rewards as determined by pendingSoul.
        uint pending = pendingSoul(pid, msg.sender);
        // [if] rewards are pending, [then] send rewards to user.
        if(pending > 0) { safeSoulTransfer(msg.sender, pending); }

        // gets: timeDelta as the time since last withdrawal.
        uint timeDelta = userDelta(pid, msg.sender);

        // gets: deltaDays as days passed using timeDelta.
        uint deltaDays = getDeltaDays(timeDelta);

        // updates: deposit, timeDelta, & deltaDays (user)
        user.amount -= amount;
        user.timeDelta = timeDelta;
        user.deltaDays = deltaDays;

        // calculates: withdrawable amount (pid, deltaDays, amount).
        (, uint withdrawableAmount) = getWithdrawable(pid, deltaDays, amount); 

        // calculates: `feeAmount` as the `amount` requested minus `withdrawableAmount`.
        uint feeAmount = amount - withdrawableAmount;

        // transfers: `feeAmount` --> DAO.
        pool.lpToken.transfer(address(dao), feeAmount);
        // transfers: withdrawableAmount amount --> user.
        pool.lpToken.transfer(address(msg.sender), withdrawableAmount);

        // updates: rewardDebt and withdrawalTime (user)
        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;
        user.withdrawalTime = block.timestamp;

        emit Withdraw(msg.sender, pid, amount, feeAmount, block.timestamp);
    }

    // enables: withdrawal without caring about rewards (for example, when rewards end).
    function emergencyWithdraw(uint pid) external nonReentrant emergencyActive {
        // gets: pool & user data (to update later).
        Pools storage pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];

        // [if] removing from staking
        if (pid == 0) {
            // [then] require SEANCE balance covers request (user).
            require(seance.balanceOf(msg.sender) >= user.amount, 'insufficient SEANCE to cover SOUL withdrawal request');
            // [then] burn seance from sender.
            seance.burn(msg.sender, user.amount); 
        }

        // transfers: lpToken to the user.
        pool.lpToken.safeTransfer(msg.sender, user.amount);

        // eliminates: user deposit and rewardDebt.
        user.amount = 0;
        user.rewardDebt = 0;

        emit EmergencyWithdraw(msg.sender, pid, user.amount);
    }

    // stakes: soul into summoner.
    function enterStaking(uint amount) public nonReentrant isActive {
        Pools storage pool = poolInfo[0];
        Users storage user = userInfo[0][msg.sender];

        updatePool(0);

        // gets: staked amount (user).
        uint stakedAmount = user.amount;

        // [if] already staked (user)
        if (stakedAmount > 0) {
            // [then] get: pending rewards.
            uint pending = pendingSoul(0, msg.sender);
            // [then] send: pending rewards.
            safeSoulTransfer(msg.sender, pending);
        }
        
        // [if] staking (ø harvest)
        if (amount > 0) {
            // [then] transfer: `amount` of SOUL from user to contract.
            pool.lpToken.transferFrom(msg.sender, address(this), amount);
            // [then] increase: stored deposit amount (user).
            user.amount += amount;
        }

        // [if] first deposit, [then] set depositTime to meow (user).
        if (user.depositTime == 0) { user.depositTime = block.timestamp; }

        // updates: reward debt (user)
        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;

        // mints & sends: requested `amount` of SEANCE to sender as a receipt.
        if (amount > 0) { seance.mint(msg.sender, amount); }

        emit Deposit(msg.sender, 0, amount, block.timestamp);
    }

    // unstake: your soul (external staker)
    function leaveStaking(uint amount) external nonReentrant isActive {
        Pools storage pool = poolInfo[0];
        Users storage user = userInfo[0][msg.sender];

        // checks: sufficient balance to cover request (user).
        require(user.amount >= amount, 'requested withdrawal exceeds staked balance');
        updatePool(0);

        // gets: pending staking pool rewards (user).
        uint pending = pendingSoul(0, msg.sender);

        // [if] sender has pending rewards, [then] transfer rewards to sender.
        if (pending > 0) { safeSoulTransfer(msg.sender, pending); }

        // [if] withdrawing from stake.
        if (amount > 0) {
            // [then] decrease: stored deposit by withdrawal amount.
            user.amount = user.amount - amount;
            // [then] burn: SEANCE in the specified `amount` (user).
            seance.burn(msg.sender, amount);
            // [then] update: reward debt (user).
            user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;
            // [then] update: withdrawal time (user).
            user.withdrawalTime = block.timestamp;
            // [then] transfer: requested SOUL (user).
            pool.lpToken.transfer(address(msg.sender), amount);
        }

        emit Withdraw(msg.sender, 0, amount, 0, block.timestamp);
    }
    
    // transfer: seance (only if there is sufficient coverage for payout).
    function safeSoulTransfer(address account, uint amount) internal {
        require(seance.balanceOf(soulAddress) >= amount, 'insufficient coverage for requested SOUL from SEANCE');
        seance.safeSoulTransfer(account, amount);
    }

    // update: weight (ma'at)
    function updateWeight(uint _weight, uint _totalWeight) external obey(maat) {
        require(weight != _weight || totalWeight != _totalWeight, 'must include a new value');
        require(_totalWeight >= _weight, 'weight cannot exceed totalWeight');

        weight = _weight;     
        totalWeight = _totalWeight;

        updateRewards(_weight, _totalWeight);

        emit WeightUpdated(_weight, _totalWeight);
    }

    // update: staking pool
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

    // update: rewards
    function updateRewards(uint _weight, uint _totalWeight) internal {
        uint share = enWei(_weight) / _totalWeight; // share of total emissions for rewarder (rewarder % total emissions)
        
        dailySoul = share * globalDailySoul; // dailySoul (for rewarder) = share (%) x globalDailySoul (soul emissions constant)
        soulPerSecond = dailySoul / 1 days; // updates: daily rewards expressed in seconds (1 days = 86,400 secs)

        emit RewardsUpdated(dailySoul, soulPerSecond);
    }

    // updates: feeDays (ma'at)
    function updateFeeDays(uint pid, uint _daysRequested) external obey(maat) {
        Pools storage pool = poolInfo[pid];
        // converts & stores requested days (enWei).
        uint _feeDays = enWei(_daysRequested);

        // gets: current fee days & ensures distinction (pool)
        uint feeDays = pool.feeDays;
        require(feeDays != _feeDays, 'must be a new value');
        
        // limits: feeDays by maxFeeDays
        require(feeDays <= maxFeeDays, 'exceeds allowable feeDays');
        
        // updates: fee days (pool)
        pool.feeDays = _feeDays;
        
        emit FeeDaysUpdated(pid, _feeDays);
    }

    // updates: dao & team addresses (isis)
    function updateAccounts(address _dao, address _team) external obey(isis) {
        require(dao != _dao || team != _team, 'must include a new account');
        dao = _dao;
        team = _team;

        emit AccountsUpdated(dao, team);
    }

    // helper functions to convert to wei and 1/100th
    function enWei(uint amount) public pure returns (uint) {  return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }
}
