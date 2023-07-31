// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../libraries/SafeERC20.sol";
import "../interfaces/IToken.sol";

pragma solidity >=0.8.0;

// the bonder of souls
contract SoulBondFantom is AccessControl, ReentrancyGuard {
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
    address private immutable SOUL_FTM = 0xa2527Af9DABf3E3B4979d7E0493b5e2C6e63dC57;        // [.√.] SOUL-WFTM
    address private immutable SOUL_USDC = 0x5cED9D6B44a1F7C927AF31A8Af26dEF60C776712;       // [.√.] SOUL-axlUSDC
    address private immutable NATIVE_USDC = 0xd1A432df5ee2Df3F891F835854ffeA072C273C65;     // [.√.] WFTM-axlUSDC
    address private immutable BTC_NATIVE = 0x44DF3a3b162826D7354b4e2495AEF097B6862069;      // [.√.] axlBTC-FTM
    address private immutable BTC_USDC = 0xC258ee426f5607cc6f003e73F705CdeE06EbBDe2;        // [.√.] axlBTC-axlUSDC
    address private immutable ETH_NATIVE = 0x9827713159B666855BdfB53CE0F16aA7b0E30847;      // [.√.] axlETH-FTM
    address private immutable ETH_USDC = 0xd9535aaA72a0eD8fd5c3F453cE4c4FA00Fc117b3 ;       // [.√.] axlETH-axlUSDC
    address private immutable USDC_USDC = 0xBBdA07f2121274ecb1a08077F37A60F7E0D36629;       // [.√.] axlUSDC - lzUSDC

    // team addresses
    address private team; // receives 1/8 soul supply
    address public dao; // recieves 1/8 soul supply

    // soul & seance addresses
    address private soulAddress = 0xe2fb177009FF39F52C0134E8007FA0e4BaAcBd07;   // FTM
    address private seanceAddress = 0x104cBF4643E371CC96E3bcbD93e29BDFc43DF2B0; // FTM

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
    bool private isEmergency;

    // pools & allocation points
    uint public poolLength;
    uint public totalAllocPoint;

    // summoner initialized state.
    bool private isInitialized;

    // pool info
    Pools[] public poolInfo;

    // user data
    mapping (uint => mapping (address => Users)) public userInfo;

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

    event Initialized(uint totalAllocPoint, uint weight, uint startTime);

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
        uint totalAllocPoint, 
        uint absDelta,
        uint timestamp
    );

    event WeightUpdated(uint weight, uint totalWeight, uint timestamp);
    event RewardsUpdated(uint dailySoul, uint soulPerSecond, uint timestamp);

    event AccountsUpdated(address dao, address team, uint timestamp);
    event EmergencyWithdraw(address account, uint pid, uint amount, uint timestamp);
    event TokensUpdated(address soul, address seance);
    event DepositRevised(uint _pid, address _user, uint _time);

    // channels the power of the isis and ma'at
    constructor() {
        team = 0x221cAc060A2257C8F77B6eb1b03e36ea85A1675A;  // FTM √
        dao = 0x1C63C726926197BD3CB75d86bCFB1DaeBcD87250;   // FTM √

        isis = keccak256("isis"); // goddess whose magic creates pools
        maat = keccak256("maat"); // goddess whose cosmic order allocates emissions

        _divinationCeremony(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, msg.sender);
        _divinationCeremony(isis, isis, msg.sender); // isis role created -- supreme divined admin
        _divinationCeremony(maat, isis, msg.sender); // ma'at role created -- isis divined admin

        // sets: soul & seance
        soul = IToken(soulAddress);
        seance = IToken(seanceAddress);
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
        addPool(400, IERC20(SOUL_FTM), true);
        addPool(200, IERC20(SOUL_USDC), true);
        addPool(200, IERC20(NATIVE_USDC), true);
        addPool(200, IERC20(BTC_NATIVE), true);
        addPool(200, IERC20(BTC_USDC), true);
        addPool(200, IERC20(ETH_NATIVE), true);
        addPool(200, IERC20(ETH_USDC), true);
        addPool(200, IERC20(USDC_USDC), true);

        // activates: initialize state
        isInitialized = true;          

        emit Initialized(totalAllocPoint, weight, block.timestamp);
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
        poolLength++;

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

            // calculates: | delta | for global allocation;
            uint absDelta 
                = isIncrease 
                    ? _allocPoint - allocPoint
                    : allocPoint - _allocPoint;

            // sets: new `pool.allocPoint`
            pool.allocPoint = _allocPoint;

            // updates: `totalAllocPoint`
            isIncrease 
                ? totalAllocPoint += absDelta
                : totalAllocPoint -= absDelta;

        emit PoolSet(pid, allocPoint, totalAllocPoint, absDelta, block.timestamp);
    }

    // view: bonus multiplier.
    function getMultiplier(uint from, uint to) internal pure returns (uint) {
        return (to - from);
    }

    // safety: in case of errors.
    function setTotalAllocPoint(uint _totalAllocPoint) external obey(isis) {
        totalAllocPoint = _totalAllocPoint;
    }

    // returns: pending soul rewards
    function pendingSoul(uint pid, address _user) external view returns (uint pendingRewards) {
        Pools storage pool = poolInfo[pid];
        Users storage user = userInfo[pid][_user];

        // gets: pool variables (for reference)
        uint accSoulPerShare = pool.accSoulPerShare;
        uint lpSupply = pool.lpSupply;

        // [if] pool is not empty and lastRewardTime has passed.
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            // [then] idenfies: `multiplier`
            uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint soulReward = multiplier * soulPerSecond * pool.allocPoint / totalAllocPoint;
            accSoulPerShare = accSoulPerShare + soulReward * 1e12 / lpSupply;
        }

        return user.amount * accSoulPerShare / 1e12 - user.rewardDebt;
    }

    // update: rewards for all pools (public)
    function massUpdatePools() public {
        // [for] all pids updates: rewards distribution.
        for (uint pid = 0; pid < poolInfo.length; ++pid) { updatePool(pid); }
    }

    // update: rewards for a given pool id (public)
    function updatePool(uint pid) public validatePoolByPid(pid) {
        Pools storage pool = poolInfo[pid];

        // [if] rewards have not yet been issued (`lastRewardTime`), [then] ends.
        if (block.timestamp <= pool.lastRewardTime) { return; }
        uint lpSupply = pool.lpSupply;

        // [if] pool is empty, [then] updates: `lastRewardTime` & ends here.
        if (lpSupply == 0) { pool.lastRewardTime = block.timestamp; return; }

        // calculates: soulReward using time sinceLastReward.
        uint multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint soulReward = multiplier * soulPerSecond * pool.allocPoint / totalAllocPoint;
        
        // calculates: divis & allocates (mints) accordingly.
        uint divi = soulReward * 1e12 / 8e12;
        // mints: 12.5% rewards to team.
        soul.mint(team, divi);
        // mints: 12.5% rewards to dao.
        soul.mint(dao, divi);
        // mints: 100% to seance (stores for rewarding).
        soul.mint(address(seance), soulReward);
        
        // updates: pool variables
        pool.accSoulPerShare = pool.accSoulPerShare + (soulReward * 1e12 / lpSupply);
        pool.lastRewardTime = block.timestamp;
    }

    // deposits: lp tokens
    function deposit(uint pid, uint amount) external nonReentrant validatePoolByPid(pid) {
        require(isInitialized, 'rewards have not yet begun');
        require(!isEmergency, 'emergency activated');
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

        // [-] updates: `amount` & `rewardDebt` & `depositTime` (for user).
        user.amount = 0;
        user.rewardDebt = 0;
        user.depositTime = 0;

        emit Bonded(msg.sender, pid, block.timestamp);
    }

    // transfer: seance (internal)
    function safeSoulTransfer(address account, uint amount) internal {
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
        
        // [-] updates: user deposit `amount`, `rewardDebt`, & `depositTime`.
        user.amount = 0;
        user.rewardDebt = 0;
        user.depositTime = 0;

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

    // helper functions to convert to/from wei
    function toWei(uint amount) public pure returns (uint) {  return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }
}
