// SPDX-License-Identifier: MIT
// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IMigrator {
    // Perform LP token migration from legacy.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.

    function migrate(IERC20 token) external returns (IERC20);
}

interface ISummoner {
    function deposit(uint _pid, uint _amount) external;
    function withdraw(uint _pid, uint _amount) external;
    function enterStaking(uint _amount) external;

    function leaveStaking(uint _amount) external; 
    function setMigrator(IMigrator _migrator) external;

    function pendingSoul(uint _pid, address _user) external view returns (uint);
    function userInfo(uint _pid, address _user) 
        external view returns (
        uint amount,                // total tokens user has provided.
        uint rewardDebt,            // reward debt (see below).
        uint rewardDebtAtTime,      // the last time user stake.
        uint lastWithdrawTime,      // the last time a user withdrew at.
        uint firstDepositTime,      // the last time a user deposited at.
        uint timeDelta,             // time passed since withdrawals.
        uint lastDepositTime        // most recent deposit time.
        );
}


pragma solidity >=0.8.0;

contract SoulHarvestDistributor {

    ISummoner public summoner = ISummoner(0xce6ccbB1EdAD497B4d53d829DF491aF70065AB5B);
    address public accountant = msg.sender;

    mapping (uint => mapping (address => Users)) public userInfo; // staker data


    // user info
    struct Users {
        uint amount;           // total tokens user has provided.
        uint rewardDebt;       // reward debt (see below).
        //   pending reward = (user.amount * pool.accSoulPerShare) - user.rewardDebt

        // the following occurs when a user +/- tokens to a pool:
        //   1. pool: `accSoulPerShare` and `lastRewardTime` update.
        //   2. user: receives pending reward.
        //   3. user: `amount` updates(+/-).
        //   4. user: `rewardDebt` updates (+/-).
    }

    event TransactionAdded(address indexed account, uint indexed pid, uint harvested);
    event DepositAdded(address indexed account, uint indexed pid, uint deposited, uint harvested);
    event WithdrawAdded(address indexed account, uint indexed pid, uint withdrawn, uint harvested);
    event HarvestAdded(address indexed account, uint indexed pid, uint harvested);
    event newAccountant(address accountant);
    
    function stakedAmount(uint pid) public view returns (uint bigStaked, uint staked) {
       (bigStaked,,,,,,) = summoner.userInfo(pid, msg.sender);
       staked = fromWei(bigStaked);

       return (bigStaked, staked);
    }

    function stakedAmount(uint pid, address account) public view returns (uint bigStaked, uint staked) {
        (bigStaked,,,,,,) = summoner.userInfo(pid, account);
        staked = fromWei(bigStaked);

        return (bigStaked, staked);

    }

    function rewardDebt(uint pid) public view returns (uint bigDebt, uint debt) {
       (,bigDebt,,,,,) = summoner.userInfo(pid, msg.sender);
        debt = fromWei(bigDebt);

        return (bigDebt, debt);    
    }

    function rewardDebt(uint pid, address account) public view returns (uint bigDebt, uint debt) {
       (,bigDebt,,,,,) = summoner.userInfo(pid, account);
       debt = fromWei(bigDebt);

        return (bigDebt, debt); 
    }

    function pendingRewards(uint pid) public view returns (uint bigPending, uint pending) {
       bigPending = summoner.pendingSoul(pid, msg.sender);
       pending = fromWei(bigPending);

       return (bigPending, pending);
    }

    function pendingRewards(uint pid, address account) public view returns (uint bigPending, uint pending) {
        bigPending = summoner.pendingSoul(pid, account);
        pending = fromWei(bigPending);

       return (bigPending, pending);
    }

    // update user's ledger with a reported transaction
    function addTransaction(bool isDeposit, uint pid, address account, uint amount, uint harvested) public {
        require(msg.sender == accountant, 'only the accountant may update ledger');
        
        // case: tokens deposited, else harvested only.
        isDeposit && amount > 0
            ? addDeposit(pid, account, amount, harvested)
            : addHarvest(pid, account, harvested);

        // case: tokens withdrawn, else harvested only. 
        !isDeposit && amount > 0
            ? addWithdrawal(pid, account, amount, harvested)
            : addHarvest(pid, account, harvested);
        
        emit TransactionAdded(account, pid, harvested);
    }

    // update user's balance with a reported deposit
    function addDeposit(uint pid, address account, uint deposited, uint harvested) public {
        require(msg.sender == accountant, 'only the accountant may update ledger');
        
        Users storage user = userInfo[pid][account];
        user.amount += deposited;

        emit DepositAdded(account, pid, deposited, harvested);
    }

    // update user's balance with a reported withdrawal
    function addWithdrawal(uint pid, address account, uint withdrawn, uint harvested) public {
        require(msg.sender == accountant, 'only the accountant may update ledger');
        
        Users storage user = userInfo[pid][account];
        user.amount += withdrawn;

        emit WithdrawAdded(account, pid, withdrawn, harvested);
    }

    // update user's balance with a manually-added deposit
    function addHarvest(uint pid, address account, uint harvested) public {
        require(msg.sender == accountant, 'only the accountant may update ledger');
        
        Users storage user = userInfo[pid][account];
        user.amount += harvested;

        emit HarvestAdded(account, pid, harvested);
    }

    function updateAccountant(address _accountant) public {
        require(_accountant == accountant, 'only accountant may update');
        
        accountant = _accountant;

        emit newAccountant(_accountant);
    }

    function fromWei(uint bigAmount) public pure returns(uint amount) {
        return bigAmount / 1E18;
    }

    function toWei(uint amount) public pure returns(uint bigAmount) {
        return amount * 1E18;
    }
}