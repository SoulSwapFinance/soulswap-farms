// SPDX-License-Identifier: MIT

/**
    vault that stakes your soul (as a single entity) & distributes the rewards accordingly to 
    the user's share of the total stake, calculated with the same logic as soul summoner.

    the user needs to approve the contract address with soul `allowance()` in order to deposit.
 */

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '../libraries/ERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '../interfaces/ISummoner.sol';

contract SoulVault is Ownable, Pausable {

    struct UserInfo {
        uint shares; // number of shares for a user
        uint lastDepositedTime; // keeps track of deposited time for potential penalty
        uint soulAtLastUserAction; // keeps track of soul deposited at the last user action
        uint lastUserActionTime; // keeps track of the last user action time
    }

    IERC20 public soul; // soul power
    IERC20 public seance; // seance circle
    ISummoner public immutable summoner;
    mapping(address => UserInfo) public userInfo;

    uint public totalShares;
    uint public lastHarvestedTime;
    address public admin = msg.sender;
    address public treasury = msg.sender;

    uint public constant MAX_PERFORMANCE_FEE = 500; // 5%
    uint public constant MAX_CALL_FEE = 100; // 1%
    uint public constant MAX_WITHDRAW_FEE = 100; // 1%
    uint public constant MAX_WITHDRAW_FEE_PERIOD = 72 hours; // 3 days

    uint public performanceFee = 200; // 2%
    uint public callFee = 25; // 0.25%
    uint public withdrawFee = 10; // 0.1%
    uint public withdrawFeePeriod = 72 hours; // 3 days

    event Deposit(address indexed sender, uint amount, uint shares, uint lastDepositedTime);
    event Withdraw(address indexed sender, uint amount, uint shares);
    event Harvest(address indexed sender, uint performanceFee, uint callFee);
   
    event Pause();
    event Unpause();

    constructor(IERC20 _soul, IERC20 _seance, ISummoner _summoner) {
        soul = _soul;
        seance = _seance;
        summoner = _summoner;

        // infinite approve
        soul.approve(address(_summoner), type(uint).max);
    }

    // checks if the msg.sender is the admin address
    modifier onlyAdmin() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }

    // checks if the msg.sender is a contract or a proxy
    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    // deposits: into soul vaul (unpaused, blocks contracts)
    function deposit(uint _amount) external whenNotPaused notContract {
        require(_amount > 0, "nothing to deposit");

        uint pool = balanceOf();
        soul.transferFrom(msg.sender, address(this), _amount);
        uint currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount * totalShares) / pool;
        } else {
            currentShares = _amount;
        }
        UserInfo storage user = userInfo[msg.sender];

        user.shares = user.shares + currentShares;
        user.lastDepositedTime = block.timestamp;

        totalShares = totalShares + currentShares;

        user.soulAtLastUserAction = (user.shares * balanceOf()) / totalShares;
        user.lastUserActionTime = block.timestamp;

        _earn();

        emit Deposit(msg.sender, _amount, currentShares, block.timestamp);
    }

    // withdraws: all claimable funds for the caller (blocks contracts)
    function withdrawAll() external notContract {
        withdraw(userInfo[msg.sender].shares);
    }

    // reinvests: soul power into soul summoner (whenNotPaused)
    function harvest() external notContract whenNotPaused {
        ISummoner(summoner).leaveStaking(0);

        uint bal = available();
        uint currentPerformanceFee = (bal * performanceFee) / 10000;
        soul.transfer(treasury, currentPerformanceFee);

        uint currentCallFee = (bal * callFee) / 10000;
        soul.transfer(msg.sender, currentCallFee);

        _earn();

        lastHarvestedTime = block.timestamp;

        emit Harvest(msg.sender, currentPerformanceFee, currentCallFee);
    }

    // sets: admin address (owner)
    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Cannot be zero address");
        admin = _admin;
    }

    // sets: treasury address (owner)
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Cannot be zero address");
        treasury = _treasury;
    }

    // sets: performance fee (admin)
    function setPerformanceFee(uint _performanceFee) external onlyAdmin {
        require(_performanceFee <= MAX_PERFORMANCE_FEE, "performanceFee cannot be more than MAX_PERFORMANCE_FEE");
        performanceFee = _performanceFee;
    }

    // sets: call fee (admin)
    function setCallFee(uint _callFee) external onlyAdmin {
        require(_callFee <= MAX_CALL_FEE, "callFee cannot be more than MAX_CALL_FEE");
        callFee = _callFee;
    }

    // sets: withdraw fee (admin)
    function setWithdrawFee(uint _withdrawFee) external onlyAdmin {
        require(_withdrawFee <= MAX_WITHDRAW_FEE, "withdrawFee cannot be more than MAX_WITHDRAW_FEE");
        withdrawFee = _withdrawFee;
    }

    // sets: withdraw fee period (admin)
    function setWithdrawFeePeriod(uint _withdrawFeePeriod) external onlyAdmin {
        require(
            _withdrawFeePeriod <= MAX_WITHDRAW_FEE_PERIOD,
            "withdrawFeePeriod cannot be more than MAX_WITHDRAW_FEE_PERIOD"
        );
        withdrawFeePeriod = _withdrawFeePeriod;
    }

    // withdraws: unexpected tokens sent to the soul vault
    function inCaseTokensGetStuck(address _token) external onlyAdmin {
        require(_token != address(soul), "Token cannot be same as deposit token");
        require(_token != address(seance), "Token cannot be same as receipt token");

        uint amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, amount);
    }

    // triggers: stopped state
    function pause() external onlyAdmin whenNotPaused {
        _pause();
        emit Pause();
    }

    // returns: to normal state (when paused)
    function unpause() external onlyAdmin whenPaused {
        _unpause();
        emit Unpause();
    }

    // calculates: expected soul harvest reward from third party (view)
    function calculateHarvestSoulRewards() external view returns (uint) {
        uint amount = ISummoner(summoner).pendingSoul(0, address(this));
        amount = amount + available();
        uint currentCallFee = (amount * callFee) / 10000;

        return currentCallFee;
    }

    // calcuates: the ttl pending rewards that may be restaked (view)
    function calculateTotalPendingSoulRewards() external view returns (uint) {
        uint amount = ISummoner(summoner).pendingSoul(0, address(this));
        amount = amount + available();

        return amount;
    }

    // calculates: the price per share (view)
    function getPricePerFullShare() external view returns (uint) {
        return totalShares == 0 ? 1e18 : (balanceOf() * 1e18) / totalShares;
    }

    // withdraws: from funds from the soul vault (not contract)
    function withdraw(uint _shares) public notContract {
        UserInfo storage user = userInfo[msg.sender];
        require(_shares > 0, "Nothing to withdraw");
        require(_shares <= user.shares, "Withdraw amount exceeds balance");

        uint currentAmount = (balanceOf() * _shares) / totalShares;
        user.shares = user.shares - _shares;
        totalShares = totalShares - _shares;

        uint bal = available();
        if (bal < currentAmount) {
            uint balWithdraw = currentAmount - bal;
            ISummoner(summoner).leaveStaking(balWithdraw);
            uint balAfter = available();
            uint diff = balAfter - bal;
            if (diff < balWithdraw) {
                currentAmount = bal + diff;
            }
        }

        if (block.timestamp < user.lastDepositedTime + withdrawFeePeriod) {
            uint currentWithdrawFee = (currentAmount * withdrawFee) / 10000;
            soul.transfer(treasury, currentWithdrawFee);
            currentAmount = currentAmount - currentWithdrawFee;
        }

        if (user.shares > 0) {
            user.soulAtLastUserAction = (user.shares * balanceOf()) / totalShares;
        } else { user.soulAtLastUserAction = 0; }

        user.lastUserActionTime = block.timestamp;
        soul.transfer(msg.sender, currentAmount);

        emit Withdraw(msg.sender, currentAmount, _shares);
    }

    // returns: ttl soul deposited by users (view)
    function available() public view returns (uint) {
        return soul.balanceOf(address(this));
    }

    // returns: total underlying soul | vault + soul summoner (view)
    function balanceOf() public view returns (uint) {
        (uint amount, , , , , ,) = ISummoner(summoner).userInfo(0, address(this));
        return soul.balanceOf(address(this)) + amount;
    }

    // deposits: into summoner to earn rewards
    function _earn() internal {
        uint bal = available();
        if (bal > 0) { ISummoner(summoner).enterStaking(bal); }
    }

    // returns: whether sender is contract to prevent targeted attacks (internal view)
    function _isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
}
