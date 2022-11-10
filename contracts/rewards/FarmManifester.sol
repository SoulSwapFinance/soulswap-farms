// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../libraries/SafeERC20.sol';
import '../libraries/ERC20.sol';

contract Farm is ReentrancyGuard, Ownable {
using SafeERC20 for IERC20;
    address public manifester;
    address public dao;
    IERC20 public rewardToken;
    IERC20 public depositToken;
    
    uint public duration;
    uint public feeDays;
    uint public dailyReward;
    uint public totalRewards;
    uint public rewardPerSecond;
    uint public accRewardPerShare;
    uint public lastRewardTime;

    bool private isManifested;
    bool private isEmergency;
    bool private isActivated;

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
    modifier isActive {
        require(isActivated, 'contract is currently paused');
        _;
    }

    event Deposit(address indexed user, uint amount, uint timestamp);
    event Withdraw(address indexed user, uint amount, uint feeAmount, uint timestamp);
    event EmergencyWithdraw(address indexed user, uint amount, uint timestamp);
    event FeeDaysUpdated(uint feeDays);

    // sets the manifester address (at creation).
    constructor() { manifester = msg.sender; }

    // called once by the manifester (at creation).
    function manifest(
        address _dao,
        address _rewardToken,
        address _depositToken,
        uint _duration,
        uint _feeDays,
        uint _dailyReward,
        uint _totalRewards
    ) external {
        require(msg.sender == manifester, "only the manifeser many manifest"); // sufficient check
        require(!isManifested, 'initialize once');
        dao = _dao;
        rewardToken = IERC20(_rewardToken);
        depositToken = IERC20(_depositToken);
        duration = _duration;
        feeDays = toWei(_feeDays);
        dailyReward = _dailyReward;
        totalRewards = _totalRewards;

        // sets: initialization state.
        isManifested = true;

        // sets: rewardPerSecond.
        rewardPerSecond = dailyReward / 1 days;
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
        uint _accRewardPerShare = accRewardPerShare;
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

    // returns: the total amount of deposited tokens.
    function getDepositSupply() public view returns (uint) {
        return depositToken.balanceOf(address(this));
    }

    // updates: the reward that is accounted for.
    function updateFarm() public {

        if (block.timestamp <= lastRewardTime) { return; }
        uint depositSupply = getDepositSupply();

        // [if] first farmer, [then] set `lastRewardTime` to meow.
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
    function deposit(uint amount) public nonReentrant isActive {

        // gets: stored data for pool and user.
        Users storage user = userInfo[msg.sender];

        updateFarm();

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


    

    // withdraw: lp tokens (external farmers)
    function withdraw(uint amount) external nonReentrant isActive {
        require(amount > 0, 'cannot withdraw zero');
        Users storage user = userInfo[msg.sender];

        require(user.amount >= amount, 'withdrawal exceeds deposit');
        updateFarm();

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
        rewardToken.safeTransfer(owner(), feeAmount);
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
    // enables: panic button (owner)
    function toggleEmergency(bool enabled) external onlyOwner {
        isEmergency = enabled;
    }

    // toggles: pause state (owner)
    function toggleActive(bool enabled) external onlyOwner {
        isActivated = enabled;
    }

    // updates: feeDays (owner)
    function updateFeeDays(uint _feeDays) external onlyOwner {
        // gets: current fee days & ensures distinction (pool)
        require(feeDays != toWei(_feeDays), 'no change requested');
        
        // limits: feeDays by default maximum of 30 days.
        require(toWei(_feeDays) <= toWei(30), 'exceeds a month of fees');
        
        // updates: fee days (pool)
        feeDays = toWei(_feeDays);
        
        emit FeeDaysUpdated(toWei(_feeDays));
    }

    /*/ HELPER FUNCTIONS /*/
    // helper functions to convert to wei and 1/100th
    function toWei(uint amount) public pure returns (uint) { return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }

}

contract FarmManifester {
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(Farm).creationCode));

    uint256 public totalFarms = 0;
    address[] public allFarms;

    mapping(address => mapping(address => address)) public getFarm; // depositToken, creatorAddress

    event FarmCreated(address indexed creatorAddress, address indexed depositToken, address dao, address rewardToken, address farm, uint duration, uint feeDays, uint totalFarms);

    function createFarm(address dao, address rewardToken, address depositToken, uint duration, uint feeDays, uint dailyReward) external returns (address farm) {
        require(rewardToken != depositToken, 'reward and deposit cannot be identical.');
        address creatorAddress = address(msg.sender);
        uint tokenDecimals = ERC20(rewardToken).decimals();
        uint totalRewards = duration * 1 days * dailyReward * tokenDecimals;

        // ensures: unique deposit-owner mapping.
        require(getFarm[depositToken][creatorAddress] == address(0), 'reward already exists'); // single check is sufficient
        
        // checks: the creator has a sufficient balance.
        require(ERC20(rewardToken).balanceOf(msg.sender) >= totalRewards, 'insufficient balance to launch farm');

        // transfers: `totalRewards` to this contract.
        ERC20(rewardToken).transferFrom(msg.sender, address(this), totalRewards);

        bytes memory bytecode = type(Farm).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(depositToken, creatorAddress));
        
        assembly { farm := create2(0, add(bytecode, 32), mload(bytecode), salt) }

        // creates: new farm based off of the inputs, then stores as an array.
        Farm(farm).manifest(dao, rewardToken, depositToken, duration, feeDays, dailyReward, totalRewards);
        
        // populates: the getFarm mapping
        getFarm[depositToken][creatorAddress] = farm;
        getFarm[creatorAddress][depositToken] = farm; // populate mapping in the reverse direction

        // stores the farm to the allFarms array
        allFarms.push(farm);

        // increments: the total number of farms
        totalFarms++;

        emit FarmCreated(creatorAddress, depositToken, rewardToken, dao, farm, duration, feeDays, totalFarms);
    }
}