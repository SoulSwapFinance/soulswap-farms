// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
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
}

interface IManifester {
    function soulDAO() external returns (address);
    function getNativeSymbol() external view returns (string memory);
    function getOracleAddress() external view returns (address);
    function getWrappedAddress() external view returns (address);
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

    IERC20 public rewardToken;
    IERC20 public depositToken;

    string public override name;
    string public override symbol;
    string public logoURI;
    
    uint public duraDays;
    uint public feeDays;
    uint public dailyReward;
    uint public totalRewards;
    uint public rewardPerSecond;
    uint public accRewardPerShare;
    uint public lastRewardTime;

    bool public isManifested;
    bool public isEmergency;
    bool public isActivated;
    bool public isSettable;

    // user info
    struct Users {
        uint amount;            // deposited amount.
        uint rewardDebt;        // reward debt (see: pendingReward).
        uint withdrawalTime;    // last withdrawal time.
        uint depositTime;       // first deposit time.
        uint timeDelta;         // seconds accounted for in fee calculation.
        uint deltaDays;         // days accounted for in fee calculation

        // the following occurs when a user +/- tokens to a pool:
        //   1. pool: `accRewardPerShare` and `lastRewardTime` update.
        //   2. user: receives pending reward.
        //   3. user: `amount` updates (+/-).
        //   4. user: `rewardDebt` updates (+/-).
        //   5. user: [if] first-timer, 
            // [then] `depositTime` updates,
            // [else] `withdrawalTime` updates.
    }

    // user info
    mapping (address => Users) public userInfo;

    // controls: emergencyWithdrawals.
    modifier emergencyActive {
        require(isEmergency, 'emergency mode is not active.');
        _;
    }

    // proxy for pausing contract.
    modifier whileActive {
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

    modifier onlyDAO() {
        require(DAO == msg.sender, "onlyDAO: caller is not the DAO address");
        _;
    }

    event Deposit(address indexed user, uint amount, uint timestamp);
    event Withdraw(address indexed user, uint amount, uint feeAmount, uint timestamp);
    event EmergencyWithdraw(address indexed user, uint amount, uint timestamp);
    event FeeDaysUpdated(uint feeDays);

    // called once by the manifester (at creation).
    function manifest(
        address _rewardToken,
        address _depositToken,
        address _DAO,
        address _manifester,
        uint _duraDays,
        uint _feeDays,
        uint _dailyReward
    ) external {
        require(!isManifested, 'initialize once');

        // sets: from input data.
        DAO = _DAO;
        manifester = IManifester(_manifester);
        rewardToken = IERC20(_rewardToken);
        depositToken = IERC20(_depositToken);
        duraDays = _duraDays;
        feeDays = toWei(_feeDays);
        dailyReward = toWei(_dailyReward);

        // sets: initialization state.
        isManifested = true;

        // sets: rewardPerSecond.
        rewardPerSecond = toWei(_dailyReward) / 1 days;

        // constructs: name that corresponds to the rewardToken.
        name = string(abi.encodePacked('Manifest: ', IERC20Metadata(address(rewardToken)).name()));
        symbol = string(abi.encodePacked(IERC20Metadata(address(rewardToken)).symbol(), '-', getNativeSymbol(), ' MP'));

        // sets: key data.
        soulDAO = manifester.soulDAO();
        totalRewards = duraDays * toWei(_dailyReward);
    }

    // returns: pending rewards for the sender.
    function pendingRewards() public view returns (uint pendingAmount) {
        return pendingRewardsAccount(msg.sender);
    }

    // returns: pending rewards for a specifed account.
    function pendingRewardsAccount(address account) public view returns (uint pendingAmount) {
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
        return user.amount * _accRewardPerShare / 1e12 - user.rewardDebt;
    }

    // returns: multiplier during a period.
    function getMultiplier(uint from, uint to) public pure returns (uint) {
        return to - from;
    }

    // returns: 
    function getNativeSymbol() public view returns (string memory) {
        return IManifester(manifester).getNativeSymbol();
    }

    function getNativePrice() public view returns (uint nativePrice) {
        address nativeOracle = IManifester(manifester).getOracleAddress();
        uint decimals = uint(IOracle(nativeOracle).decimals());
        uint latestPrice = uint(IOracle(nativeOracle).latestAnswer());
        uint divisor = 10**decimals;
        nativePrice = latestPrice / divisor;
    }

    // returns: price per token
    function getPricePerToken() public view returns (uint pricePerToken) {
        uint nativePriceUSD = getNativePrice();
        IERC20 WNATIVE = IERC20(IManifester(manifester).getWrappedAddress());
        uint wnativeBalance = WNATIVE.balanceOf(address(depositToken));
        uint totalSupply = depositToken.totalSupply();
        uint nativeValue = wnativeBalance * nativePriceUSD;

        pricePerToken = nativeValue * 2 / totalSupply;
    }
    
    // returns: TVL
    function getTVL() public view returns (uint tvl) {
        uint pricePerToken = getPricePerToken();
        uint depositBalance = depositToken.balanceOf(address(this));
        tvl = depositBalance * pricePerToken;
    }

    // returns: the total amount of deposited tokens.
    function getDepositSupply() public view returns (uint) {
        return depositToken.balanceOf(address(this));
    }

    // updates: the reward that is accounted for.
    function updateManifestation() public {

        if (block.timestamp <= lastRewardTime) { return; }
        uint depositSupply = getDepositSupply();

        // [if] first manifestationer, [then] set `lastRewardTime` to meow.
        if (depositSupply == 0) { lastRewardTime = block.timestamp; return; }

        // gets: multiplier from time elasped since pool began issuing rewards.
        uint multiplier = getMultiplier(lastRewardTime, block.timestamp);
        uint reward = multiplier * rewardPerSecond;

        accRewardPerShare += (reward * 1e12 / depositSupply);
        lastRewardTime = block.timestamp;
    }

        // returns: user delta is the time since user either last withdrew OR first deposited OR 0.
	function getUserDelta(address account) public view returns (uint timeDelta) {
        // gets: stored `user` data.
        Users storage user = userInfo[account];

        // [if] has never withdrawn & has deposited, [then] returns: `timeDelta` as the seconds since first `depositTime`.
        if (user.withdrawalTime == 0 && user.depositTime > 0) { return timeDelta = block.timestamp - user.depositTime; }
            // [else if] `user` has withdrawn, [then] returns: `timeDelta` as the time since the last withdrawal.
            else if(user.withdrawalTime > 0) { return timeDelta = block.timestamp - user.withdrawalTime; }
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

    // USER FUNCTIONS //

    // harvests: pending rewards.
    function harvest() public {
        require(pendingRewards() > 0);
        deposit(0);
    }

    // deposit: tokens.
    function deposit(uint amount) public nonReentrant whileActive {

        // gets: stored data for pool and user.
        Users storage user = userInfo[msg.sender];

        updateManifestation();

        // [if] already deposited (user)
        if (user.amount > 0) {
            // [then] gets: pendingReward.
        uint pendingReward = user.amount * accRewardPerShare / 1e12 - user.rewardDebt;
                // [if] rewards pending, [then] transfer to user.
                if(pendingReward > 0) { 
                    // ensures: only a full payout is made, else fails.
                    require(rewardToken.balanceOf(address(this)) >= pendingReward, 'insufficient balance for reward payout');
                    rewardToken.transfer(msg.sender, pendingReward);
                }
        }

        // [if] depositing more
        if (amount > 0) {
            // [then] transfer depositToken from user to contract
            depositToken.safeTransferFrom(address(msg.sender), address(this), amount);
            // [then] increment deposit amount (user).
            user.amount += amount;
        }

        // updates: reward debt (user).
        user.rewardDebt = user.amount * accRewardPerShare / 1e12;

        // [if] first time depositing (user)
        if (user.depositTime == 0) {
            // [then] update depositTime
            user.depositTime = block.timestamp;
        }
        
        emit Deposit(msg.sender, amount, block.timestamp);
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

    function getLogo() public view returns (string memory) {
        return logoURI;
    }  

    // withdraw: lp tokens (external manifestationers)
    function withdraw(uint amount) external nonReentrant whileActive {
        require(amount > 0, 'cannot withdraw zero');
        Users storage user = userInfo[msg.sender];

        require(user.amount >= amount, 'withdrawal exceeds deposit');
        updateManifestation();

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

        // updates: rewardDebt and withdrawalTime (user)
        user.rewardDebt = user.amount * accRewardPerShare / 1e12;
        user.withdrawalTime = block.timestamp;

        emit Withdraw(msg.sender, amount, feeAmount, block.timestamp);
    }

    // enables: withdrawal without caring about rewards (for example, when rewards end).
    function emergencyWithdraw() external nonReentrant emergencyActive {
        // gets: pool & user data (to update later).
        Users storage user = userInfo[msg.sender];

        // transfers: depositToken to the user.
        depositToken.safeTransfer(msg.sender, user.amount);

        // eliminates: user deposit `amount` & `rewardDebt`.
        user.amount = 0;
        user.rewardDebt = 0;

        // updates: user `withdrawTime`.
        user.withdrawalTime = block.timestamp;

        emit EmergencyWithdraw(msg.sender, user.amount, user.withdrawalTime);
    }

    /*/ ADMINISTRATIVE FUNCTIONS /*/
    // enables: panic button (onlyDAO)
    function toggleEmergency(bool enabled) external onlyDAO {
        isEmergency = enabled;
    }

    // toggles: pause state (onlyDAO)
    function toggleActive(bool enabled) external onlyDAO whileSettable {
        isActivated = enabled;
    }

    // updates: LogoURI (onlyDAO, whileSettable)
    function setLogoURI(string memory _logoURI) external onlyDAO whileSettable {
        logoURI = _logoURI;
    }

    // updates: feeDays (onlyDAO)
    function updateFeeDays(uint _feeDays) external onlyDAO {
        // gets: current fee days & ensures distinction (pool)
        require(feeDays != toWei(_feeDays), 'no change requested');
        
        // limits: feeDays by default maximum of 30 days.
        require(toWei(_feeDays) <= toWei(30), 'exceeds a month of fees');
        
        // updates: fee days (pool)
        feeDays = toWei(_feeDays);
        
        emit FeeDaysUpdated(toWei(_feeDays));
    }

    // sets: DAO address (onlyDAO)
    function setDAO(address _DAO) external onlyDAO {
        require(_DAO != address(0), 'cannot set to zero address');
        // updates: DAO adddress
        DAO = _DAO;
    }

    /*/ SOUL-RESTRICTED (OVERRIDE) FUNCTIONS /*/
    // enables soulDAO to update logoURI (onlySOUL)
    function setLogo(string memory _logoURI) external onlySOUL {
        logoURI = _logoURI;
    }

    // prevents: any funny business (onlySOUL)
    function toggleSettable(bool enabled) external onlySOUL {
        isSettable = enabled;
    }

    function toggleActiveOverride(bool enabled) external onlySOUL {
        isActivated = enabled;
    }

    // sets: soulDAO address (onlySOUL)
    function setSoulDAO(address _soulDAO) external onlySOUL {
        require(_soulDAO != address(0), 'cannot set to zero address');
        // updates: soulDAO adddress
        soulDAO = _soulDAO;
    }

    /*/ HELPER FUNCTIONS /*/
    function toWei(uint amount) public pure returns (uint) { return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }

}

contract Manifester is IManifester, Ownable {
    using SafeERC20 for IERC20;
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(Manifestation).creationCode));

    ISoulSwapFactory public Factory;
    uint256 public totalManifestations;
    address[] public manifestations;

    address public override soulDAO;
    address public wnativeAddress;

    IERC20 public WNATIVE;
    IOracle public nativeOracle;

    string public nativeSymbol;
    uint public bloodSacrifice;

    bool public isPaused;

    mapping(address => mapping(address => address)) public getManifestation; // depositToken, creatorAddress

    event SummonedManifestation(
            address indexed creatorAddress, 
            address indexed depositToken, 
            address rewardToken, 
            address manifestation, 
            uint duraDays, 
            uint feeDays, 
            uint totalManifestations
    );

    event Paused(address pauserAddress);

    // proxy for pausing contract.
    modifier whileActive {
        require(!isPaused, 'contract is currently paused');
        _;
    }

    // constructor(address _factoryAddress, address _wnativeAddress) {
    constructor() {
        Factory = ISoulSwapFactory(0x1120e150dA9def6Fe930f4fEDeD18ef57c0CA7eF);
        bloodSacrifice = toWei(1);
        WNATIVE = IERC20(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
        nativeSymbol = 'FTM';
        wnativeAddress = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
        soulDAO = msg.sender;
        nativeOracle = IOracle(0xf4766552D15AE4d256Ad41B6cf2933482B0680dc);
    }

    function createManifestation(address _rewardToken, uint _duraDays, uint _feeDays, uint _dailyReward) external whileActive returns (address manifestation) {
        address depositToken = Factory.getPair(address(WNATIVE), _rewardToken);

        // [if] pair does not exist
        if (depositToken == address(0)) {
            // [then] create pair and store as the depositToken.
            createDepositToken(_rewardToken);
            depositToken = Factory.getPair(address(WNATIVE), _rewardToken);
        }

        // ensures: `rewardToken` and `depositToken` are distinct.
        require(_rewardToken != depositToken, 'reward and deposit cannot be identical.');
        // ensures: reward token has 18 decimals.
        require(ERC20(_rewardToken).decimals() == 18, 'reward token must be 18 decimals'); // neccessary for rewards distribution calculation.
    
        uint rewards = getTotalRewards(_duraDays, _dailyReward);
        uint sacrifice = getSacrifice(fromWei(rewards));
        uint total = rewards + sacrifice;

        // ensures: depositToken is never 0x.
        require(depositToken != address(0));
        // ensures: unique deposit-owner mapping.
        require(getManifestation[depositToken][msg.sender] == address(0), 'reward already exists'); // single check is sufficient
        
        // checks: the creator has a sufficient balance to cover both rewards + sacrifice.
        require(ERC20(_rewardToken).balanceOf(msg.sender) >= total, 'insufficient balance to launch manifestation');

        // generates the creation code, salt, then assembles a create2Address for the new manifestation.
        bytes memory bytecode = type(Manifestation).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(depositToken, msg.sender));
        
        assembly { manifestation := create2(0, add(bytecode, 32), mload(bytecode), salt) }

        // transfers: sacrifice directly to soulDAO.
        IERC20(_rewardToken).safeTransferFrom(msg.sender, soulDAO, sacrifice);
        
        // transfers: `totalRewards` to the manifestation contract.
        IERC20(_rewardToken).safeTransferFrom(msg.sender, manifestation, rewards);

        // creates: new manifestation based off of the inputs, then stores as an array.
        Manifestation(manifestation).manifest(_rewardToken, depositToken, msg.sender, address(this), _duraDays, _feeDays, _dailyReward);
        
        // populates: the getManifestation mapping (also in reverse direction).
        getManifestation[depositToken][msg.sender] = manifestation;
        getManifestation[msg.sender][depositToken] = manifestation; 

        // stores the manifestation to the manifestations[] array
        manifestations.push(manifestation);

        // increments: the total number of manifestations
        totalManifestations++;

        emit SummonedManifestation(msg.sender, depositToken, _rewardToken, manifestation, _duraDays, _feeDays, totalManifestations);
    }

    /*/ GETTER FUNCTIONS /*/
    function getTotalRewards(uint duraDays, uint dailyReward) public pure returns (uint) {
        uint totalRewards = duraDays * toWei(dailyReward);
        return totalRewards;
    }

    function getSacrifice(uint rewards) public view returns (uint) {
        uint sacrifice = (rewards * bloodSacrifice) / 100;
        return sacrifice;
    }

    function getNativeSymbol() external view override returns (string memory) {
        return nativeSymbol;
    }

    function getOracleAddress() external override pure returns (address _oracleAddress) {
        return _oracleAddress;
    }
    
    function getWrappedAddress() external override pure returns (address _wnativeAddress) {
        return _wnativeAddress;
    }

    function getInfo(uint id) public view returns (address mAddress, string memory name, string memory symbol, uint rewardPerSecond) {
        mAddress = address(manifestations[id]);
        Manifestation manifestation = Manifestation(mAddress);

        name = manifestation.name();
        symbol = manifestation.symbol();

        rewardPerSecond = manifestation.rewardPerSecond();
    }

    function createDepositToken(address rewardToken) public {
        Factory.createPair(address(WNATIVE), rewardToken);
    }

    /*/ ADMIN FUNCTIONS /*/
    function updateFactory(address _factoryAddress) external onlyOwner {
        Factory = ISoulSwapFactory(_factoryAddress);
    }

    function updateDAO(address _DAOAddress) external onlyOwner {
        soulDAO = _DAOAddress;
    }

    function updateSacrifice(uint _sacrifice) external onlyOwner {
        bloodSacrifice = toWei(_sacrifice);
    }

    function togglePause(bool enabled) external onlyOwner {
        isPaused = enabled;

        emit Paused(msg.sender);
    }

    /*/ HELPER FUNCTIONS /*/
    function toWei(uint amount) public pure returns (uint) { return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }
}