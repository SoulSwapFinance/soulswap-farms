// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '../libraries/SafeERC20.sol';
import '../libraries/ERC20.sol';

interface ISoulSwapFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    event SetFeeTo(address indexed user, address indexed _feeTo);
    event SetMigrator(address indexed user, address indexed _migrator);
    event FeeToSetter(address indexed user, address indexed feeToSetter);

    function feeTo() external view returns (address _feeTo);
    function feeToSetter() external view returns (address _fee);
    function migrator() external view returns (address _migrator);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setMigrator(address) external;
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IManifestation {
    function name() external returns (string memory);
    function symbol() external returns (string memory);
    function logoURI() external returns (string memory);

    function startTime() external returns (uint);
    function endTime() external returns (uint);

    function getTVL() external returns (uint);
    function getTotalDeposit() external returns (uint);
}

interface IManifester {
    function soulDAO() external returns (address);
    function wnativeAddress() external returns (address);
    function nativeSymbol() external returns (string memory);
    function getNativePrice() external view returns (int);
}

interface IOracle {
  function latestAnswer() external view returns (int256);
  function decimals() external view returns (uint8);
  function latestTimestamp() external view returns (uint256);
}


contract Manifestation is IManifestation, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public creatorAddress;
    IManifester public manifester;
    address public DAO;
    address public soulDAO;
    address public wnativeAddress;
    string public nativeSymbol;

    IERC20 public rewardToken;
    IERC20 public depositToken;

    string public override name;
    string public override symbol;
    string public override logoURI;
    
    uint public duraDays;
    uint public feeDays;
    uint public dailyReward;
    uint public totalRewards;
    uint public rewardPerSecond;
    uint public accRewardPerShare;
    uint public lastRewardTime;

    uint public override startTime;
    uint public override endTime;

    bool public isManifested;
    bool public isSetup;
    bool public isEmergency;
    bool public isActivated;
    bool public isSettable;

    // user info
    struct Users {
        uint amount;            // deposited amount.
        uint rewardDebt;        // reward debt (see: pendingReward).
        uint withdrawTime;      // last withdrawal time.
        uint depositTime;       // first deposit time.
        uint timeDelta;         // seconds accounted for in fee calculation.
        uint deltaDays;         // days accounted for in fee calculation
    }

    // user info
    mapping (address => Users) public userInfo;

    // controls: emergencyWithdrawals.
    modifier emergencyActive {
        require(isEmergency, 'emergency mode is not active.');
        _;
    }

    // proxy for pausing contract.
    modifier isWithdrawable(uint amount) {
        require(startTime != 0, 'start time has not been set');
        require(amount > 0, 'cannot withdraw zero');
        require(startTime >= block.timestamp, 'rewards have not yet begun');
        require(isActivated, 'contract is currently paused');
        _;
    }
   
    // proxy for pausing contract.
    modifier isDepositable(uint amount) {
        require(startTime != 0, 'start time has not been set');
        require(amount > 0, 'cannot deposit zero');
        require(endTime < block.timestamp, 'the reward period has ended');
        require(isActivated, 'contract is currently paused');
        _;
    }

    // proxy for setting contract.
    modifier whileSettable {
        require(isSettable, 'contract is currently not settable');
        _;
    }

    // designates: soul access (for (rare) overrides).
    modifier onlySOUL() {
        require(soulDAO == msg.sender, "onlySOUL: caller is not the soulDAO address");
        _;
    }

    // ensures: only the DAO address is the sender.
    modifier onlyDAO() {
        require(DAO == msg.sender, "onlyDAO: caller is not the DAO address");
        _;
    }

    event Harvested(address indexed user, uint amount, uint timestamp);
    event Deposited(address indexed user, uint amount, uint timestamp);
    event Withdrawn(address indexed user, uint amount, uint feeAmount, uint timestamp);
    event EmergencyWithdrawn(address indexed user, uint amount, uint timestamp);
    event FeeDaysUpdated(uint feeDays);

    // initializes: manifestation by the manifester (at creation).
    function manifest(
        address _rewardToken,
        address _depositToken,
        address _DAO,
        address _manifester

        ) external {
        require(!isManifested, 'initialize once');

        // sets: from input data.
        rewardToken = IERC20(_rewardToken);
        depositToken = IERC20(_depositToken);
        DAO = _DAO;
        manifester = IManifester(_manifester);


        // sets: initial states.
        isManifested = true;
        isSettable = true;

        // sets: key data.
        soulDAO = manifester.soulDAO();
        wnativeAddress = manifester.wnativeAddress();
        nativeSymbol = manifester.nativeSymbol();

        creatorAddress = _DAO;

        // constructs: name that corresponds to the rewardToken.
        name = string(abi.encodePacked('Manifest: ', ERC20(address(rewardToken)).name()));
        symbol = string(abi.encodePacked(ERC20(address(rewardToken)).symbol(), '-', nativeSymbol, ' MP'));
    }
    
    function setRewards(uint _duraDays, uint _feeDays, uint _dailyReward) external {
        require(msg.sender == address(manifester), 'only the Manifester may set rewards');
        require(!isSetup, 'already setup');

        // sets: key info.
        duraDays = _duraDays;
        feeDays = toWei(_feeDays);
        dailyReward = toWei(_dailyReward);
        rewardPerSecond = toWei(_dailyReward) / 1 days;
        totalRewards = duraDays * toWei(_dailyReward);

        // sets: setup state.
        isSetup = true;
            
    }

    // updates: rewards, so that they are accounted for.
    function update() public {

        if (block.timestamp <= lastRewardTime) { return; }
        uint depositSupply = getTotalDeposit();

        // [if] first manifestationer, [then] set `lastRewardTime` to meow.
        if (depositSupply == 0) { lastRewardTime = block.timestamp; return; }

        // gets: multiplier from time elasped since pool began issuing rewards.
        uint multiplier = getMultiplier(lastRewardTime, block.timestamp);
        uint reward = multiplier * rewardPerSecond;

        accRewardPerShare += (reward * 1e12 / depositSupply);
        lastRewardTime = block.timestamp;
    }

    ///////////////////////////////
        /*/ VIEW FUNCTIONS /*/
    ///////////////////////////////

    // returns: pending rewards for a specifed account.
    function getPendingRewards(address account) external view returns (uint pendingAmount) {
        // gets: pool and user data
        Users storage user = userInfo[account];

        // gets: `accRewardPerShare` & `lpSupply` (pool)
        uint _accRewardPerShare = accRewardPerShare; // uses: local variable for reference use.
        uint depositSupply = depositToken.balanceOf(address(this));

        // [if] holds deposits & rewards issued at least once (pool)
        if (block.timestamp > lastRewardTime && depositSupply != 0) {
            // gets: multiplier from the time since now and last time rewards issued (pool)
            uint multiplier = getMultiplier(lastRewardTime, block.timestamp);
            // get: reward as the product of the elapsed emissions and the share of soul rewards (pool)
            uint reward = multiplier * rewardPerSecond;
            // adds: product of reward and 1e12
            _accRewardPerShare = accRewardPerShare + reward * 1e12 / depositSupply;
        }

        // returns: rewardShare for user minus the amount paid out (user)
        pendingAmount = user.amount * _accRewardPerShare / 1e12 - user.rewardDebt;

        return pendingAmount;
    }

    // returns: multiplier during a period.
    function getMultiplier(uint from, uint to) public pure returns (uint multiplier) {
        multiplier = to - from;

        return multiplier;
    }

    // returns: price per token
    function getPricePerToken() public view returns (uint pricePerToken) {
        uint nativePriceUSD = uint(IManifester(manifester).getNativePrice());
        IERC20 WNATIVE = IERC20(wnativeAddress);
        uint wnativeBalance = WNATIVE.balanceOf(address(depositToken));
        uint totalSupply = depositToken.totalSupply();
        uint nativeValue = wnativeBalance * nativePriceUSD;
        pricePerToken = nativeValue * 2 / totalSupply;

        return pricePerToken;
    }

    // returns: TVL
    function getTVL() external view override returns (uint tvl) {
        uint pricePerToken = getPricePerToken();
        uint totalDeposited = getTotalDeposit();
        tvl = totalDeposited * pricePerToken;
        
        return tvl;
    }

    // returns: the total amount of deposited tokens.
    function getTotalDeposit() public view override returns (uint totalDeposited) {
        totalDeposited = depositToken.balanceOf(address(this));
        return totalDeposited;
    }

    // returns: user delta is the time since user either last withdrew OR first deposited OR 0.
	function getUserDelta(address account) public view returns (uint timeDelta) {
        // gets: stored `user` data.
        Users storage user = userInfo[account];

        // [if] has never withdrawn & has deposited, [then] returns: `timeDelta` as the seconds since first `depositTime`.
        if (user.withdrawTime == 0 && user.depositTime > 0) { return timeDelta = block.timestamp - user.depositTime; }
            // [else if] `user` has withdrawn, [then] returns: `timeDelta` as the time since the last withdrawal.
            else if(user.withdrawTime > 0) { return timeDelta = block.timestamp - user.withdrawTime; }
                // [else] returns: `timeDelta` as 0, since the user has never deposited.
                else return timeDelta = 0;
	}

    // gets: days based off a given timeDelta (seconds).
    function getDeltaDays(uint timeDelta) public pure returns (uint deltaDays) {
        deltaDays = timeDelta < 1 days ? 0 : timeDelta / 1 days;
        return deltaDays;     
    }

     // returns: feeRate and timeDelta.
    function getFeeRate(uint deltaDays) public view returns (uint feeRate) {
        // calculates: rateDecayed (converts to wei).
        uint rateDecayed = toWei(deltaDays);
    
        // [if] more time has elapsed than wait period
        if (rateDecayed >= feeDays) {
            // [then] set feeRate to 0.
            feeRate = 0;
        } else { // [else] reduce feeDays by the rateDecayed.
            feeRate = feeDays - rateDecayed;
        }

        return feeRate;
    }

    // returns: feeAmount and with withdrawableAmount for a given amount
    function getWithdrawable(uint deltaDays, uint amount) public view returns (uint _feeAmount, uint _withdrawable) {
        // gets: feeRate
        uint feeRate = fromWei(getFeeRate(deltaDays));
        // gets: feeAmount
        uint feeAmount = (amount * feeRate) / 100;
        // calculates: withdrawable amount
        uint withdrawable = amount - feeAmount;

        return (feeAmount, withdrawable);
    }

    // returns: reward period (start, end).
    function getRewardPeriod() public view returns (uint start, uint end) {
        start = startTime;
        end = endTime;
        return (start, end);
    }


    //////////////////////////////////////
        /*/ ACCOUNT (TX) FUNCTIONS /*/
    //////////////////////////////////////

    // harvests: pending rewards.
    function harvest() external nonReentrant {
        Users storage user = userInfo[msg.sender];

        // updates: calculations.
        update();

        // gets: pendingRewards and requires pending reward.
        uint pendingReward = user.amount * accRewardPerShare / 1e12 - user.rewardDebt;
        require(pendingReward > 0, 'there is nothing to harvest');

        // ensures: only a full payout is made, else fails.
        require(rewardToken.balanceOf(address(this)) >= pendingReward, 'insufficient balance for reward payout');
        
        // transfers: reward toke to user.
        rewardToken.transfer(msg.sender, pendingReward);

        // updates: reward debt (user).
        user.rewardDebt = user.amount * accRewardPerShare / 1e12;

        emit Harvested(msg.sender, pendingReward, block.timestamp);

    }

    // deposit: tokens.
    function deposit(uint amount) external nonReentrant isDepositable(amount) {
        // gets: stored data for pool and user.
        Users storage user = userInfo[msg.sender];

        // updates: calculations.
        update();

        // [if] already deposited (user)
        if (user.amount > 0) {
            // [then] gets: pendingReward.
            uint pendingReward = user.amount * accRewardPerShare / 1e12 - user.rewardDebt;
                // [if] rewards pending, [then] transfer to user.
                if(pendingReward > 0) { 
                    // [then] ensures: only a full payout is made, else fails.
                    require(rewardToken.balanceOf(address(this)) >= pendingReward, 'insufficient balance for reward payout');
                    rewardToken.transfer(msg.sender, pendingReward);
                }
        }

        // transfers: depositToken from user to contract
        depositToken.safeTransferFrom(address(msg.sender), address(this), amount);

        // adds: deposit amount (for user).
        user.amount += amount;

        // updates: reward debt (user).
        user.rewardDebt = user.amount * accRewardPerShare / 1e12;

        // [if] first deposit
        if (user.depositTime == 0) {
            // [then] update depositTime
            user.depositTime = block.timestamp;
        }

        emit Deposited(msg.sender, amount, block.timestamp);
    }

    // withdraws: deposited tokens.
    function withdraw(uint amount) external nonReentrant isWithdrawable(amount) {
        // gets: stored data for the account.
        Users storage user = userInfo[msg.sender];

        require(user.amount >= amount, 'withdrawal exceeds deposit');
        
        // helps: manage calculations.
        update();

        // gets: pending rewards as determined by pendingSoul.
        uint pendingReward = user.amount * accRewardPerShare / 1e12 - user.rewardDebt;
        // [if] rewards are pending, [then] send rewards to user.
        if(pendingReward > 0) { 
            // ensures: only a full payout is made, else fails.
            require(rewardToken.balanceOf(address(this)) >= pendingReward, 'insufficient balance for reward payout');
            rewardToken.safeTransfer(msg.sender, pendingReward); 
        }

        // gets: timeDelta as the time since last withdrawal.
        uint timeDelta = getUserDelta(msg.sender);

        // gets: deltaDays as days passed using timeDelta.
        uint deltaDays = getDeltaDays(timeDelta);

        // updates: deposit, timeDelta, & deltaDays (user)
        user.amount -= amount;
        user.timeDelta = timeDelta;
        user.deltaDays = deltaDays;

        // calculates: withdrawable amount (deltaDays, amount).
        (, uint withdrawableAmount) = getWithdrawable(deltaDays, amount); 

        // calculates: `feeAmount` as the `amount` requested minus `withdrawableAmount`.
        uint feeAmount = amount - withdrawableAmount;

        // transfers: `feeAmount` --> owner.
        rewardToken.safeTransfer(DAO, feeAmount);
        // transfers: withdrawableAmount amount --> user.
        rewardToken.safeTransfer(address(msg.sender), withdrawableAmount);

        // updates: rewardDebt and withdrawTime (user)
        user.rewardDebt = user.amount * accRewardPerShare / 1e12;
        user.withdrawTime = block.timestamp;

        emit Withdrawn(msg.sender, amount, feeAmount, block.timestamp);
    }

    // enables: withdrawal without caring about rewards (for example, when rewards end).
    function emergencyWithdraw() external nonReentrant emergencyActive {
        // gets: pool & user data (to update later).
        Users storage user = userInfo[msg.sender];

        // helps: manage calculations.
        update();

        // transfers: depositToken to the user.
        depositToken.safeTransfer(msg.sender, user.amount);

        // eliminates: user deposit `amount` & `rewardDebt`.
        user.amount = 0;
        user.rewardDebt = 0;

        // updates: user `withdrawTime`.
        user.withdrawTime = block.timestamp;

        emit EmergencyWithdrawn(msg.sender, user.amount, user.withdrawTime);
    }


    ///////////////////////////////
        /*/ VIEW FUNCTIONS /*/
    ///////////////////////////////
    
    // returns: key user info.
    function getUserInfo(address account) external view returns (uint amount, uint rewardDebt, uint withdrawTime, uint depositTime, uint timeDelta, uint deltaDays) {
        Users storage user = userInfo[account];
        return(user.amount, user.rewardDebt, user.withdrawTime, user.depositTime, user.timeDelta, user.deltaDays);
    }


    ////////////////////////////////
        /*/ ADMIN FUNCTIONS /*/
    ////////////////////////////////

    // enables: panic button (onlyDAO, whileSettable)
    function toggleEmergency(bool enabled) external onlyDAO whileSettable {
        isEmergency = enabled;
    }

    // toggles: pause state (onlyDAO, whileSettable)
    function toggleActive(bool enabled) external onlyDAO whileSettable {
        isActivated = enabled;
    }

    // updates: LogoURI (onlyDAO, whileSettable)
    function setLogo(string memory _logoURI) external onlyDAO whileSettable {
        logoURI = _logoURI;
    }

    // updates: feeDays (onlyDAO, whileSettable) todo
    function setFeeDays(uint _feeDays) external onlyDAO whileSettable {
        // gets: current fee days & ensures distinction (pool)
        require(feeDays != toWei(_feeDays), 'no change requested');
        
        // limits: feeDays by default maximum of 30 days.
        require(toWei(_feeDays) <= toWei(30), 'exceeds a month of fees');
        
        // updates: fee days (pool)
        feeDays = toWei(_feeDays);
        
        emit FeeDaysUpdated(toWei(_feeDays));
    }

    // sets: startTime & endTime (onlyDAO)
    function setDelay(uint delayDays) external onlyDAO {
        require(startTime == 0, 'startTime has already been set');
        
        // converts: delayDays into a unix timeDelay variable (in seconds).
        uint timeDelay = delayDays * 1 days;

        // calculates: start (in seconds) as now + timeDelay.
        uint start = block.timestamp + timeDelay;
        
        // ensures: start time has not yet past.
        require(start > block.timestamp, 'start must be in the future');

        // calculates: duration (in seconds)
        uint duration = duraDays * 1 days;
        
        // sets: startTime.
        startTime = start;

        // sets: startTime.
        endTime = start + duration;
    }

    // sets: DAO address (onlyDAO)
    function setDAO(address _DAO) external onlyDAO {
        require(_DAO != address(0), 'cannot set to zero address');
        // updates: DAO adddress
        DAO = _DAO;
    }


    //////////////////////////////////////////
        /*/ SOUL (OVERRIDE) FUNCTIONS /*/
    //////////////////////////////////////////

    // prevents: funny business (onlySOUL).
    function toggleSettable(bool enabled) external onlySOUL {
        isSettable = enabled;
    }
    
    // overrides: feeDays (onlySOUL)
    function setFeeDaysOverride(uint _feeDays) external onlySOUL {
        // gets: current fee days & ensures distinction (pool)
        require(feeDays != toWei(_feeDays), 'no change requested');
        
        // limits: feeDays by default maximum of 30 days.
        require(toWei(_feeDays) <= toWei(30), 'exceeds a month of fees');
        
        // updates: fee days (pool)
        feeDays = toWei(_feeDays);
        
        emit FeeDaysUpdated(toWei(_feeDays));
    }

    // overrides: active state (onlySOUL).
    function toggleActiveOverride(bool enabled) external onlySOUL {
        isActivated = enabled;
    }

    // overrides logoURI (onlySOUL).
    function setLogoOverride(string memory _logoURI) external onlySOUL {
        logoURI = _logoURI;
    }

    // sets: soulDAO address (onlySOUL).
    function setSoulDAO(address _soulDAO) external onlySOUL {
        require(_soulDAO != address(0), 'cannot set to zero address');
        // updates: soulDAO adddress
        soulDAO = _soulDAO;
    }


    ///////////////////////////////
        /*/ HELPER FUNCTIONS /*/
    ///////////////////////////////

    function toWei(uint amount) public pure returns (uint) { return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }
}

contract Manifester is IManifester {
    using SafeERC20 for IERC20;
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(Manifestation).creationCode));

    ISoulSwapFactory public SoulSwapFactory;
    uint256 public totalManifestations;

    address[] public manifestations;
    address public override soulDAO;

    IOracle public nativeOracle;
    uint public oracleDecimals;

    string public override nativeSymbol;
    address public override wnativeAddress;

    uint public bloodSacrifice;
    bool public isPaused;


    mapping(address => mapping(uint => address)) public getManifestation; // depositToken, id

    event SummonedManifestation(
            uint indexed id,
            address indexed depositToken, 
            address rewardToken, 
            address creatorAddress, 
            address manifestation
    );

    event Paused(address msgSender);
    event UpdatedSacrifice(address msgSender);
    event UpdatedDAO(address msgSender);

    // proxy for pausing contract.
    modifier whileActive {
        require(!isPaused, 'contract is currently paused');
        _;
    }

    // restricts: certain functions to soulDAO-only.
    modifier onlySOUL() {
        require(soulDAO == msg.sender, "onlySOUL: caller is not the soulDAO address");
        _;
    }

    constructor() {
        SoulSwapFactory = ISoulSwapFactory(0x1120e150dA9def6Fe930f4fEDeD18ef57c0CA7eF);
        bloodSacrifice = toWei(1);
        nativeSymbol = 'FTM';
        wnativeAddress = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
        soulDAO = msg.sender;
        nativeOracle = IOracle(0xf4766552D15AE4d256Ad41B6cf2933482B0680dc);
        oracleDecimals = nativeOracle.decimals();
    }

    function createManifestation(address rewardToken, uint duraDays, uint feeDays, uint dailyReward) external whileActive returns (address manifestation, uint id) {
        address depositToken = SoulSwapFactory.getPair(wnativeAddress, rewardToken);
        // ensures: reward token has 18 decimals, which is needed for reward calculations.
        require(ERC20(rewardToken).decimals() == 18, 'reward token must be 18 decimals');

        // [if] pair does not exist
        if (depositToken == address(0)) {
            // [then] creates: pair and stores as depositToken.
            createDepositToken(rewardToken);
            depositToken = SoulSwapFactory.getPair(wnativeAddress, rewardToken);
        }

        // creates: variables for usage.
        id = manifestations.length;
        uint rewards = getTotalRewards(duraDays, dailyReward);
        uint sacrifice = getSacrifice(fromWei(rewards));
        uint total = rewards + sacrifice;

        // ensures: depositToken is never 0x.
        require(depositToken != address(0));
        // ensures: unique depositToken-id mapping.
        require(getManifestation[depositToken][id] == address(0), 'reward already exists'); // single check is sufficient
        
        // checks: the creator has a sufficient balance to cover both rewards + sacrifice.
        require(ERC20(rewardToken).balanceOf(msg.sender) >= total, 'insufficient balance to launch manifestation');

        // generates the creation code, salt, then assembles a create2Address for the new manifestation.
        bytes memory bytecode = type(Manifestation).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(depositToken, id));
        assembly { manifestation := create2(0, add(bytecode, 32), mload(bytecode), salt) }

        // transfers: sacrifice directly to soulDAO.
        IERC20(rewardToken).safeTransferFrom(msg.sender, soulDAO, sacrifice);
        
        // transfers: `totalRewards` to the manifestation contract.
        IERC20(rewardToken).safeTransferFrom(msg.sender, manifestation, rewards);

        // creates: new manifestation based off of the inputs, then stores as an array.
        // inputs: rewardToken, depositToken, DAO, manifester.
        Manifestation(manifestation).manifest(rewardToken, depositToken, msg.sender, address(this));
        
        // sets: the rewards data for the newly-created manifestation.
        // inputs: duraDays, feeDays, dailyReward.aa
        Manifestation(manifestation).setRewards(duraDays, feeDays, dailyReward);
        
        // populates: the getManifestation mapping.
        getManifestation[depositToken][id] = manifestation;

        // stores the manifestation to the manifestations[] array
        manifestations.push(manifestation);

        // increments: the total number of manifestations
        totalManifestations++;

        emit SummonedManifestation(id, depositToken, rewardToken, msg.sender, manifestation);
    }

    // creates: deposit token (as reward-native pair).
    function createDepositToken(address rewardToken) public {
        SoulSwapFactory.createPair(wnativeAddress, rewardToken);
    }

    //////////////////////////////
        /*/ VIEW FUNCTIONS /*/
    //////////////////////////////

    // returns: native price.
    function getNativePrice() public view override returns (int) {
        int latestAnswer = IOracle(nativeOracle).latestAnswer();
        return latestAnswer;
    }

    // returns: total rewards.
    function getTotalRewards(uint duraDays, uint dailyReward) public pure returns (uint) {
        uint totalRewards = duraDays * toWei(dailyReward);
        return totalRewards;
    }

    // returns: sacrifice amount.
    function getSacrifice(uint rewards) public view returns (uint) {
        uint sacrifice = (rewards * bloodSacrifice) / 100;
        return sacrifice;
    }

    // returns: info for a given id.
    function getInfo(uint id) external view returns (
        address mAddress, 
        string memory name, 
        string memory symbol, 
        string memory logoURI,

        address rewardToken,
        address depositToken,

        uint rewardPerSecond,
        uint rewardRemaining,
        uint startTime,
        uint endTime,
        uint dailyReward, 
        uint feeDays) {
        mAddress = address(manifestations[id]);
        Manifestation manifestation = Manifestation(mAddress);

        name = manifestation.name();
        symbol = manifestation.symbol();

        logoURI = manifestation.logoURI();

        rewardToken = address(manifestation.rewardToken());
        depositToken = address(manifestation.depositToken());
    
        rewardPerSecond = manifestation.rewardPerSecond();
        rewardRemaining = ERC20(rewardToken).balanceOf(mAddress);

        startTime = manifestation.startTime();
        endTime = manifestation.endTime();
        dailyReward = manifestation.dailyReward();
        feeDays = manifestation.feeDays();
    }

    // returns: user info for a given id.
    function getUserInfo(uint id, address account) external view returns (
        address mAddress, uint amount, uint rewardDebt, uint withdrawTime, uint depositTime, uint timeDelta, uint deltaDays) {
        mAddress = address(manifestations[id]);
        Manifestation manifestation = Manifestation(mAddress);
        (amount, rewardDebt, withdrawTime, depositTime, timeDelta, deltaDays) = manifestation.getUserInfo(account);
    }


    ///////////////////////////////
        /*/ ADMIN FUNCTIONS /*/
    ///////////////////////////////

    function updateFactory(address _factoryAddress) external onlySOUL {
        SoulSwapFactory = ISoulSwapFactory(_factoryAddress);
    }

    function updateDAO(address _soulDAO) external onlySOUL {
        soulDAO = _soulDAO;

        emit UpdatedDAO(msg.sender);
    }

    function updateSacrifice(uint _sacrifice) external onlySOUL {
        bloodSacrifice = toWei(_sacrifice);

        emit UpdatedSacrifice(msg.sender);
    }

    function togglePause(bool enabled) external onlySOUL {
        isPaused = enabled;

        emit Paused(msg.sender);
    }


    ////////////////////////////////
        /*/ HELPER FUNCTIONS /*/
    ////////////////////////////////

    function toWei(uint amount) public pure returns (uint) { return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }
}