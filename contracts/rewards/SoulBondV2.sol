// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../libraries/SafeERC20.sol";
import "../libraries/Operable.sol";
import "../interfaces/IToken.sol";

pragma solidity ^0.8.0;

// the bonder of souls
contract SoulBond is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // user info
    struct Users {
        uint amount;           // total tokens user has provided.
        uint rewardDebt;       // reward debt (see below).
        uint depositTime;      // last deposit time.

        // the following occurs when a user +/- tokens to a pool:
        //   1. pool: `accSoulPerShare` and `lastRewardTime` update.
        //   2. pool: `lpSupply` and `lastRewardTime` update.
        //   3. user: `amount` updates(+/-).
        //   4. user: `rewardDebt` updates (+/-).
    }

    // pool info
    struct Pools {
        IERC20 lpToken;         // lp token ierc20 contract.
        uint allocPoint;        // allocation points assigned | SOUL per second.
        uint lastRewardTime;    // most recent time SOUL distribution occurred.
        uint accSoulPerShare;   // accumulated SOUL per share, times 1e12.
        uint lpSupply;          // total amount accounted for in pool (virtual balance).
    }

    // pair addresses
    address public immutable soul_avax;
    address public immutable soul_usdc;
    address public immutable usdc_avax;
    address public immutable eth_avax;
    address public immutable btc_avax;
    address public immutable usdc_dai;

    // team addresses
    address public team; // receives 1/8 soul supply
    address public dao; // recieves 1/8 soul supply

    // soul & seance addresses
    address private soulAddress;
    address private seanceAddress;

    // tokens: soul & seance
    IToken public soul;
    IToken public seance;

    // chain share of overall emissions
    uint public totalWeight;
    uint public weight;

    // soul x day x this.chain
    uint public immutable globalDailySoul = 250_000; // = weight * 250K * 1e18;
    uint public dailySoul; // = weight * globalDailySoul * 1e18;

    // soul x second x this.chain
    uint public soulPerSecond; // = dailySoul / 86400;

    // timestamp when soul rewards began (initialized)
    uint public startTime;

    // emergency state
    bool public isEmergency;

    // pools & allocation points
    uint public immutable poolLength = 6;
    uint public totalAllocPoint;

    // summoner initialized state.
    bool public isInitialized;

    // fee state.
    bool public isBondMode;

    Pools[] public poolInfo; // pool info
    mapping (uint => mapping (address => Users)) public userInfo; // user data

    // divinated roles
    bytes32 public isis; // soul summoning goddess of magic
    bytes32 public maat; // goddess of cosmic order

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

    // controls: emergencyWithdrawals.
    modifier emergencyActive {
        require(isEmergency, 'emergency mode is not active.');
        _;
    }

    // validates: pool existance
    modifier validatePoolByPid(uint pid) {
        require(pid < poolInfo.length, 'pool does not exist');
        _;
    }

    event Deposit(
        address indexed user, 
        uint indexed pid, 
        uint amount, 
        uint timestamp
    );

    event Bonded(
        address indexed user, 
        uint indexed pid, 
        uint timeStamp
    );

    event Initialized(
        address team, address dao, address soulAddress, address seanceAddress, 
        uint totalAllocPoint, uint weight, uint startTime
    );

    event PoolAdded(
        uint pid, 
        uint allocPoint, 
        IERC20 lpToken, 
        uint totalAllocPoint,
        uint timestamp
    );

    event PoolSet(
        uint pid, 
        uint allocPoint, 
        uint timestamp
    );

    event WeightUpdated(uint weight, uint totalWeight, uint timestamp);
    event RewardsUpdated(uint dailySoul, uint soulPerSecond, uint timestamp);

    event AccountsUpdated(address dao, address team, uint timestamp);
    event EmergencyWithdraw(address account, uint pid, uint amount, uint timestamp);
    event TokensUpdated(address soul, address seance);
    event DepositRevised(uint _pid, address _user, uint _time);

    // channels the power of the isis and ma'at
    constructor(
        address _team,
        address _dao,
        address _soulAddress,
        address _seanceAddress,
        address _soul_avax,
        address _soul_usdc,
        address _usdc_avax,
        address _eth_avax,
        address _btc_avax,
        address _usdc_dai
    ) {
        team = _team;
        dao = _dao;

        isis = keccak256("isis"); // goddess whose magic creates pools
        maat = keccak256("maat"); // goddess whose cosmic order allocates emissions

        _divinationCeremony(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, msg.sender);
        _divinationCeremony(isis, isis, msg.sender); // isis role created -- supreme divined admin
        _divinationCeremony(maat, isis, dao); // ma'at role created -- isis divined admin

        // sets: soul & seance addreses
        soulAddress = _soulAddress;
        seanceAddress = _seanceAddress;

        // sets: soul & seance
        soul = IToken(_soulAddress);
        seance = IToken(_seanceAddress);

        // sets: liquidity pool addresses
        soul_avax = _soul_avax;
        soul_usdc = _soul_usdc;
        usdc_avax = _usdc_avax;
        eth_avax = _eth_avax;
        btc_avax = _btc_avax;
        usdc_dai = _usdc_dai;
    } 

    function _divinationCeremony(bytes32 _role, bytes32 _adminRole, address _account) 
        internal returns (bool) {
            _setupRole(_role, _account);
            _setRoleAdmin(_role, _adminRole);
        return true;
    }

    /*/ EXTERNAL TRANSACTIONS /*/

    // activates: rewards (isis)
    function initialize( uint _weight ) external obey(isis) {
        require(!isInitialized, 'already initialized');

        // updates: global constants
        startTime = block.timestamp;
        totalWeight = 1000;
        weight = _weight;

        // updates: dailySoul and soulPerSecond
        updateRewards(weight, totalWeight);

        // deploys: all pools at once
        addPool(250, IERC20(soul_avax), true);
        addPool(150, IERC20(soul_usdc), true);
        addPool(150, IERC20(usdc_avax), true);
        addPool(150, IERC20(eth_avax), true);
        addPool(150, IERC20(btc_avax), true);
        addPool(150, IERC20(usdc_dai), true);

        // activates: initialize state
        isInitialized = true;          

        emit Initialized(team, dao, soulAddress, seanceAddress, totalAllocPoint, weight, block.timestamp);
    }

    // sets: allocation for a given pair (@ initialization)
    function addPool(uint _allocPoint, IERC20 _lpToken, bool _withUpdate) internal {
        if (_withUpdate) { massUpdatePools(); }

        totalAllocPoint += _allocPoint;
        
        poolInfo.push(
        Pools({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: block.timestamp > startTime ? block.timestamp : startTime,
            accSoulPerShare: 0,
            lpSupply: 0
        }));
        
        uint pid = poolInfo.length;

        emit PoolAdded(pid, _allocPoint, _lpToken, totalAllocPoint, block.timestamp);
    }

    // sets: allocation points (ma'at)
    function set(uint pid, uint _allocPoint, bool withUpdate) 
        external isSummoned validatePoolByPid(pid) obey(maat) {
            Pools storage pool = poolInfo[pid];
            // requires: change requested.
            require(pool.allocPoint != _allocPoint, 'no change requested');

            // [if] update requested, [then] updates: all pools.
            if (withUpdate) { massUpdatePools(); }

            // gets: current allocation point (for reference)
            uint allocPoint = pool.allocPoint;
            
            // identifies: treatment of new allocation.
            bool isIncrease = _allocPoint > allocPoint;

            // sets: new `pool.allocPoint`
            pool.allocPoint = _allocPoint;

            // updates: global `totalAllocPoint`
            if (isIncrease) { totalAllocPoint += allocPoint; }
            else { totalAllocPoint -= allocPoint; }

        emit PoolSet(pid, allocPoint, block.timestamp);
    }

    // returns: pending soul rewards
    function pendingSoul(uint pid, address _user) external view returns (uint pendingRewards) {
        Pools memory pool = poolInfo[pid];
        Users memory user = userInfo[pid][_user];

        // gets: pool variables (for reference)
        uint accSoulPerShare = pool.accSoulPerShare;
        uint lpSupply = pool.lpSupply;
        uint allocPoint = pool.allocPoint;
        
        // gets: user variables (for reference)
        uint userDeposit = user.amount;
        uint rewardDebt = user.rewardDebt;

        // [if] pool is not empty and lastRewardTime has passed.
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            // [then] idenfies: `sinceLastReward`
            uint sinceLastReward = pool.lastRewardTime - block.timestamp;
            uint soulReward = sinceLastReward * soulPerSecond * allocPoint / totalAllocPoint;
            accSoulPerShare = accSoulPerShare + (soulReward * 1e12 / lpSupply);
        }

        return userDeposit * accSoulPerShare / 1e12 - rewardDebt;
    }

    // update: rewards for all pools (public)
    function massUpdatePools() public {
        // [for] all pids updates: rewards distribution.
        for (uint pid = 0; pid < poolInfo.length; ++pid) { updatePool(pid); }
    }

    // update: rewards for a given pool id (public)
    function updatePool(uint pid) public validatePoolByPid(pid) {
        Pools storage pool = poolInfo[pid]; 
        
        // gets: variables for calculation reference (vs. updates).
        uint accSoulPerShare = pool.accSoulPerShare;
        uint lpSupply = pool.lpSupply;
        uint lastRewardTime = pool.lastRewardTime;
        uint allocPoint = pool.allocPoint;

        // [if] rewards have not yet been issued (`lastRewardTime`), [then] ends.
        if (block.timestamp <= lastRewardTime) { return; }

        // [if] pool is empty, [then] updates: `lastRewardTime` & ends here.
        if (lpSupply == 0) { pool.lastRewardTime = block.timestamp; return; }

        // calculates: soulReward using time sinceLastReward.
        uint sinceLastReward = lastRewardTime - block.timestamp;
        uint soulReward = sinceLastReward * soulPerSecond * allocPoint / totalAllocPoint;
        
        // calculates: divis & allocates (mints) accordingly.
        uint divi = soulReward * 1e12 / 8e12;
        // mints: 12.5% rewards to team.
        soul.mint(team, divi);
        // mints: 12.5% rewards to dao.
        soul.mint(dao, divi);
        // mints: 100% to seance (stores for rewarding).
        soul.mint(address(seance), soulReward);
        
        // updates: pool variables
        pool.accSoulPerShare = accSoulPerShare + (soulReward * 1e12 / lpSupply);
        pool.lastRewardTime = block.timestamp;
    }

    // deposits: lp tokens
    function deposit(uint pid, uint amount) external nonReentrant validatePoolByPid(pid) {
        require(isInitialized, 'rewards have not yet begun');
        require(amount > 0, 'must deposit more than 0');

        Pools storage pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];

        updatePool(pid);

        // transfers: assets (LP) from user to dao.
        pool.lpToken.transferFrom(msg.sender, dao, amount);
        
        // [+] updates: stored `lpSupply` (for pool).
        pool.lpSupply += amount;

        // [+] updates: stored deposit `amount` (for user).
        user.amount += amount;

        // updates: stored `rewardDebt` for user.
        user.rewardDebt = user.amount * pool.accSoulPerShare / 1e12;  

        // [if] first time depositing (user)
        if (user.depositTime == 0) {
            // [then] update depositTime
            user.depositTime = block.timestamp;
        }

        emit Deposit(msg.sender, pid, amount, block.timestamp);
    }
    
    // bond: lp tokens (external bonders)
    function bond(uint pid) external nonReentrant validatePoolByPid(pid) {
        Pools storage pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];

        require(user.amount > 0, 'zero balance: deposit before bonding.');
        
        updatePool(pid);

        uint pending = user.amount * pool.accSoulPerShare / 1e12 - user.rewardDebt;

        // [if] user has pending rewards, then send.
        if (pending > 0) { safeSoulTransfer(msg.sender, pending); }
        
        // [-] updates: `lpSupply` (for pool).
        pool.lpSupply -= user.amount;

        // [-] updates: `amount` & `rewardDebt` (for user).
        user.amount = 0;
        user.rewardDebt = 0;

        emit Bonded(msg.sender, pid, block.timestamp);
    }

    // transfer: seance (internal)
    function safeSoulTransfer(address account, uint amount) internal {
        // todo: add require
        seance.safeSoulTransfer(account, amount);
    }

    // ** UPDATE FUNCTIONS ** // 

    // updates: weight (maat)
    function updateWeights(uint _weight, uint _totalWeight) external obey(maat) {
        require(weight != _weight || totalWeight != _totalWeight, 'must be at least one new value');
        require(_totalWeight >= _weight, 'weight cannot exceed totalWeight');

        weight = _weight;     
        totalWeight = _totalWeight;

        updateRewards(weight, totalWeight);

        emit WeightUpdated(weight, totalWeight, block.timestamp);
    }

    // updates: rewards (internal)
    function updateRewards(uint _weight, uint _totalWeight) internal {
        uint share = toWei(_weight) / _totalWeight; // share of ttl emissions for chain (chain % ttl emissions)
        
        dailySoul = share * globalDailySoul; // dailySoul (for this.chain) = share (%) x globalDailySoul
        soulPerSecond = dailySoul / 1 days; // updates: daily rewards expressed in seconds (1 days = 86,400 secs)

        emit RewardsUpdated(dailySoul, soulPerSecond, block.timestamp);
    }

    // enables: withdrawal without caring about rewards (for example, when rewards end).
    function emergencyWithdraw(uint pid) external nonReentrant emergencyActive {
        // gets: pool & user data (uses storage bc updates).
        Pools storage pool = poolInfo[pid];
        Users storage user = userInfo[pid][msg.sender];

        uint withdrawAmount = user.amount;

        // [-] updates: reduces stored pool `lpSupply` by withdrawAmount.
        pool.lpSupply -= withdrawAmount;
        
        // [-] updates: user deposit `amount` & `rewardDebt`.
        user.amount = 0;
        user.rewardDebt = 0;

        emit EmergencyWithdraw(msg.sender, pid, withdrawAmount, block.timestamp);
    }

    // ADMIN FUNCTIONS //

    // update accounts: dao & team addresses (isis)
    function updateAccounts(address _dao, address _team) external obey(isis) {
        require(dao != _dao || team != _team, 'must be a new account');

        dao = _dao;
        team = _team;

        emit AccountsUpdated(dao, team, block.timestamp);
    }

    // update tokens: soul & seance addresses (isis)
    function updateTokens(address _soulAddress, address _seanceAddress) external obey(isis) {
        require(soulAddress != _soulAddress|| seanceAddress != _seanceAddress, 'must be a new token address');

        soul = IToken(_soulAddress);
        seance = IToken(_seanceAddress);

        emit TokensUpdated(_soulAddress, _seanceAddress);
    }
    
    // enables: panic button (ma'at)
    function toggleEmergency(bool enabled) external obey(maat) {
        isEmergency = enabled;
    }

    // VIEWS && HELPERS //

    // helper functions to convert to/from wei
    function toWei(uint amount) public pure returns (uint) {  return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }
}