// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './SoulPower.sol';
import './SeanceCircle.sol';

// the summoner of souls | ownership transferred to a governance smart contract 
// upon sufficient distribution + the community's desire to self-govern.

contract SoulSummoner is AccessControl, ReentrancyGuard {

    // user info
    struct Users {
        uint amount;           // total tokens user has provided.
        uint rewardDebt;       // reward debt (see below).
        uint rewardDebtAtTime; // the last time user stake.
        uint lastWithdrawTime; // the last time a user withdrew at.
        uint firstDepositTime; // the last time a user deposited at.
        uint timeDelta;        // time passed since withdrawals.
        uint lastDepositTime;  // most recent deposit time.

        //   pending reward = (user.amount * pool.accSoulPerShare) - user.rewardDebt

        // the following occurs when a user +/- tokens to a pool:
        //   1. pool: `accSoulPerShare` and `lastRewardTime` update.
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
    address public supreme; // has supreme role

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

    // decay rate on withdrawal fee of 1%.
    uint public immutable dailyDecay = enWei(1);

    // start rate for the withdrawal fee.
    uint public startRate;

    Pools[] public poolInfo; // pool info
    mapping (uint => mapping (address => Users)) public userInfo; // staker data

    // divinated roles
    bytes32 public isis; // soul summoning goddess of magic
    bytes32 public maat; // goddess of cosmic order

    event RoleDivinated(bytes32 role, bytes32 supreme);

    // restricted to the council of the role passed as an object to obey (role)
    modifier obey(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    // prevents: early reward distribution
    modifier isSummoned {
        require(isInitialized, 'rewards have not yet begun');
        _;
    }

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount, uint timeStamp);

    event Initialized(address team, address dao, address soul, address seance, uint totalAllocPoint, uint weight);
    event PoolAdded(uint pid, uint allocPoint, IERC20 lpToken, uint totalAllocPoint);
    event PoolSet(uint pid, uint allocPoint);

    event WeightUpdated(uint weight, uint totalWeight);
    event RewardsUpdated(uint dailySoul, uint soulPerSecond);
    event StartRateUpdated(uint startRate);

    event AccountsUpdated(address dao, address team, address admin);
    event TokensUpdated(address soul, address seance);
    event DepositRevised(uint _pid, address _user, uint _time);

    // validates: pool exists
    modifier validatePoolByPid(uint pid) {
        require(pid < poolInfo.length, 'pool does not exist');
        _;
    }

    // channels the power of the isis and ma'at to the deployer (deployer)
    constructor() {
        supreme = 0x81Dd37687c74Df8F957a370A9A4435D873F5e5A9;    // multi-sig safe
        team = 0x36d0164e87B58427c4153c089aeDDa8Ec0B80B9D;      // team wallet
        dao = 0x1C63C726926197BD3CB75d86bCFB1DaeBcD87250;      // dao treasury (multi-sig)

        isis = keccak256("isis"); // goddess of magic who creates pools
        maat = keccak256("maat"); // goddess of cosmic order who allocates emissions

        _divinationCeremony(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, supreme);
        _divinationCeremony(isis, isis, supreme); // isis role created -- supreme divined admin
        _divinationCeremony(maat, isis, dao); // maat role created -- isis divined admin
    } 

    function _divinationCeremony(bytes32 _role, bytes32 _adminRole, address _account) 
        internal returns (bool) {
            _setupRole(_role, _account);
            _setRoleAdmin(_role, _adminRole);
        return true;
    }

    // validate: pool uniqueness to eliminate duplication risk (internal view)
    function checkPoolDuplicate(IERC20 _token) internal view {
        uint length = poolInfo.length;

        for (uint pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _token, 'duplicated pool');
        }
    }

    // activates: rewards (owner)
    function initialize() external obey(isis) {
        require(!isInitialized, 'already initialized');

        soulAddress = 0xe2fb177009FF39F52C0134E8007FA0e4BaAcBd07;
        seanceAddress = 0x124B06C5ce47De7A6e9EFDA71a946717130079E6;

        // [required]: update global constants
        startTime = block.timestamp;
        totalWeight = 1000;
        weight = 1000;
        startRate = enWei(14);
        uint allocPoint = 1000;
        soul  = SoulPower(soulAddress);
        seance = SeanceCircle(seanceAddress);

        // updates: dailySoul and soulPerSecond
        updateRewards(weight, totalWeight); 

        // adds: staking pool
        poolInfo.push(Pools({
            lpToken: soul,
            allocPoint: allocPoint,
            lastRewardTime: startTime,
            accSoulPerShare: 0
        }));

        isInitialized = true;           // triggers: initialize state
        totalAllocPoint += allocPoint; // kickstarts: total allocation

        emit Initialized(team, dao, soulAddress, seanceAddress, totalAllocPoint, weight);
    }

    // returns: amount of pools
    function poolLength() external view returns (uint) { return poolInfo.length; }

    // add: new pool (isis)
    function addPool(uint _allocPoint, IERC20 _lpToken, bool _withUpdate) 
        public isSummoned obey(isis) { // isis: the soul summoning goddess whose power transcends them all
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

    // set: allocation points (maat)
    function set(uint pid, uint allocPoint, bool withUpdate) 
        external isSummoned validatePoolByPid(pid) obey(maat) {
            if (withUpdate) { massUpdatePools(); } // updates all pools
            
            uint prevAllocPoint = poolInfo[pid].allocPoint;
            poolInfo[pid].allocPoint = allocPoint;
            
            if (prevAllocPoint != allocPoint) {
                totalAllocPoint = totalAllocPoint - prevAllocPoint + allocPoint;
                
                updateStakingPool(); // updates only selected pool
        }

        emit PoolSet(pid, allocPoint);
    }

    // view: user delta
	function userDelta(uint256 _pid, address _user) public view returns (uint256 delta) {
        Users memory user = userInfo[_pid][_user];

        return user.lastWithdrawTime > 0
            ? block.timestamp - user.lastWithdrawTime
            : block.timestamp - user.firstDepositTime;
	}

    // view: bonus multiplier (public view)
    function getMultiplier(uint from, uint to) public view returns (uint) {
        return (to - from) * bonusMultiplier; // todo: minus parens
    }

    // returns: decay rate for a pid (public view)
    function getFeeRate(uint pid, uint timeDelta) public view returns (uint feeRate) {
        uint daysPassed = timeDelta < 1 days ? 0 : timeDelta / 1 days;
        uint rateDecayed = enWei(daysPassed);
        uint _rate = rateDecayed >= startRate ? 0 : startRate - rateDecayed;
        
        // returns 0 for SAS
        return pid == 0 ? 0 : _rate;
    }

    // returns: feeAmount and with withdrawableAmount for a given pid and amount
    function getWithdrawable(uint pid, uint timeDelta, uint amount) public view returns (uint _feeAmount, uint _withdrawable) {
        uint feeRate = fromWei(getFeeRate(pid, timeDelta));
        uint feeAmount = (amount * feeRate) / 100;
        uint withdrawable = amount - feeAmount;

        return (feeAmount, withdrawable);
    }

    // view: pending soul rewards (external)
    function pendingSoul(uint pid, address _user) external view returns (uint pendingAmount) {
        Pools storage pool = poolInfo[pid];
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
        
        uint divi = soulReward * 1e12 / 8e12;   // 12.5% rewards
        uint divis = divi * 2;                  // total divis
        uint shares = soulReward - divis;       // net shares
        
        soul.mint(team, divi);
        soul.mint(dao, divi);
        soul.mint(address(seance), shares);

        pool.accSoulPerShare = pool.accSoulPerShare + (soulReward * 1e12 / lpSupply);
        pool.lastRewardTime = block.timestamp;
    }

    // deposit: lp tokens (lp owner)
    function deposit(uint pid, uint amount) external nonReentrant validatePoolByPid(pid) {
        require (pid != 0, 'deposit SOUL by staking');

        Pools storage pool = poolInfo[pid];
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
            user.amount += amount;
        }

        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;

        // marks timestamp for first deposit
        user.firstDepositTime = 
            user.firstDepositTime > 0 
                ? user.firstDepositTime
                : block.timestamp;

        emit Deposit(msg.sender, pid, amount);
    }

    // withdraw: lp tokens (external farmers)
    function withdraw(uint pid, uint amount) external nonReentrant validatePoolByPid(pid) {
        require (pid != 0, 'withdraw SOUL by unstaking');
        Pools storage pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];

        require(user.amount >= amount, 'withdraw not good');
        updatePool(pid);

        uint pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;

        if(pending > 0) { safeSoulTransfer(msg.sender, pending); }

        if(amount > 0) {
            if(user.lastDepositTime > 0){
				user.timeDelta = block.timestamp - user.lastDepositTime; }
			else { user.timeDelta = block.timestamp - user.firstDepositTime; }
            
            user.amount = user.amount - amount;
            
        }
        
        uint timeDelta = userInfo[pid][msg.sender].timeDelta;
        (, uint withdrawable) = getWithdrawable(pid, timeDelta, amount); // removes feeAmount from amount
        uint feeAmount = amount - withdrawable;

        pool.lpToken.transfer(address(dao), feeAmount);
        pool.lpToken.transfer(address(msg.sender), withdrawable);

        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;
        user.lastWithdrawTime = block.timestamp;

        emit Withdraw(msg.sender, pid, amount, block.timestamp);
    }

    // stake: soul into summoner (external)
    function enterStaking(uint amount) external nonReentrant {
        Pools storage pool = poolInfo[0];
        Users storage user = userInfo[0][msg.sender];
        updatePool(0);

        if (user.amount > 0) {
            uint pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;
            if(pending > 0) {
                safeSoulTransfer(msg.sender, pending);
            }
        } 
        
        if(amount > 0) {
            pool.lpToken.transferFrom(address(msg.sender), address(this), amount);
            user.amount = user.amount + amount;
        }

        // marks timestamp for first deposit
        user.firstDepositTime = 
            user.firstDepositTime > 0 
                ? user.firstDepositTime
                : block.timestamp;

        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;

        seance.mint(msg.sender, amount);
        emit Deposit(msg.sender, 0, amount);
    }

    // unstake: your soul (external staker)
    function leaveStaking(uint amount) external nonReentrant {
        Pools storage pool = poolInfo[0];
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
        user.lastWithdrawTime = block.timestamp;
        
        seance.burn(msg.sender, amount);
        emit Withdraw(msg.sender, 0, amount, block.timestamp);
    }
    
    // transfer: seance (internal)
    function safeSoulTransfer(address account, uint amount) internal {
        seance.safeSoulTransfer(account, amount);
    }

    // ** UPDATE FUNCTIONS ** // 

    // update: weight (maat)
    function updateWeights(uint _weight, uint _totalWeight) external obey(maat) {
        require(weight != _weight || totalWeight != _totalWeight, 'must be at least one new value');
        require(_totalWeight >= _weight, 'weight cannot exceed totalWeight');

        weight = _weight;     
        totalWeight = _totalWeight;

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

    // update: multiplier (maat)
    function updateMultiplier(uint _bonusMultiplier) external obey(maat) {
        bonusMultiplier = _bonusMultiplier;
    }

    // update: rewards (internal)
    function updateRewards(uint _weight, uint _totalWeight) internal {
        uint share = enWei(_weight) / _totalWeight; // share of ttl emissions for chain (chain % ttl emissions)
        
        dailySoul = share * (250_000); // dailySoul (for this.chain) = share (%) x 250K (soul emissions constant)
        soulPerSecond = dailySoul / 1 days; // updates: daily rewards expressed in seconds (1 days = 86,400 secs)

        emit RewardsUpdated(dailySoul, soulPerSecond);
    }

    // update: startRate (maat)
    function updateStartRate(uint _startRate) public obey(maat) {
        require(startRate != enWei(_startRate));
        startRate = enWei(_startRate);
        
        emit StartRateUpdated(startRate);
    }

    // update accounts: dao, team, and supreme addresses (isis)
    function updateAccounts(address _dao, address _team, address _supreme) external obey(isis) {
        require(dao != _dao || team != _team || supreme != _supreme, 'must be a new account');

        dao = _dao;
        team = _team;
        supreme = _supreme;

        emit AccountsUpdated(dao, team, supreme);
    }

    // update tokens: soul and seance addresses (isis)
    function updateTokens(address _soul, address _seance) external obey(isis) {
        require(soul != IERC20(_soul) || seance != IERC20(_seance), 'must be a new token address');

        soul = SoulPower(_soul);
        seance = SeanceCircle(_seance);

        emit TokensUpdated(_soul, _seance);
    }

    // manual override to reassign the first deposit time for a given (pid, account)
    function reviseDeposit(uint _pid, address _user, uint256 _time) public obey(maat) {
        Users storage user = userInfo[_pid][_user];
        user.firstDepositTime = _time;

        emit DepositRevised(_pid, _user, _time);
	}

    // ** HELPER FUNCTIONS ** // 

    // helper functions to convert to wei and 1/100th
    function enWei(uint amount) public pure returns (uint) {  return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }
}
