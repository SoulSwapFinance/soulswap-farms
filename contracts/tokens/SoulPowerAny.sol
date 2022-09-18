// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/AccessControl.sol";

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    function totalSupply() external view returns (uint);

    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint value
    );
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            codehash := extcodehash(account)
        }
        return (codehash != 0x0 && codehash != accountHash);
    }
}

library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

contract SoulPowerAny is IERC20, AccessControl {
    using SafeERC20 for IERC20;
    string public name;
    string public symbol;
    uint8 public immutable override decimals;

    // used for crosschain pureposes
    address public underlying;
    bool public constant underlyingIsMinted = false;
    bool public isUnderlyingImmutable;

    /// @dev records amount of SOUL owned by account.
    mapping(address => uint) public override balanceOf;
    uint private _totalSupply;

    // init flag for setting immediate vault, needed for CREATE2 support
    bool private _init;

    // primary controller of the token contract (trivial)
    address public vault;

    // toggles swapout vs vault.burn so multiple events are triggered
    bool private _vaultOnly;

    // checks for revocation of init.
    bool private _initRevoked;

    // restricts ability to deposit and withdraq
    bool private _depositEnabled;
    bool private _withdrawEnabled;

    // mapping used to verify minters & vaults
    mapping(address => bool) public isMinter;
    mapping(address => bool) public isVault;

    // arrays composed of minter & vaults
    address[] public minters;
    address[] public vaults;

    // supreme & roles
    address public supreme; // supreme divine
    bytes32 public anunnaki; // admin role
    bytes32 public thoth; // minter role
    bytes32 public sophia; // burner role

    // events
    event NewSupreme(address supreme);
    event Rethroned(bytes32 role, address oldAccount, address newAccount);
    event LogSwapin(
        bytes32 indexed txhash,
        address indexed account,
        uint amount
    );
    event LogSwapout(
        address indexed account,
        address indexed bindaddr,
        uint amount
    );

    // modifiers
    modifier onlySupreme() {
        require(msg.sender == supreme, 'sender must be supreme');
        _;
    }

    // restricted to the house of the role passed as an object to obey
    modifier obey(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    function owner() external view returns (address) {
        return supreme;
    }

    function mpc() external view returns (address) {
        return supreme;
    }

    // toggles permissions for _vaultOnly
    function setVaultOnly(bool enabled) external onlySupreme {
        _vaultOnly = enabled;
    }

    // initializes (when not revoked) [ onlySupreme ]
    function initVault(address _vault) external onlySupreme {
        require(!_initRevoked, 'initialization revoked');
        vault = _vault;
        isMinter[_vault] = true;
    }

    // toggles ability to init [ onlySupreme ]
    function toggleInit(bool enabled) external onlySupreme {
        require(!_initRevoked, 'initialization revoked');
        _init = enabled;
    }

    // revokes ability to re-initialize [ onlySupreme ]
    function revokeInit() external onlySupreme {
        require(!_initRevoked, 'initialization already revoked');
        _initRevoked = true;
    }

    // checks whether sender has divine `role` (public view)
    function hasDivineRole(bytes32 role) public view returns (bool) {
        return hasRole(role, msg.sender);
    }

    // sets minter address [ onlySupreme ]
    function setMinter(address _minter) external onlySupreme {
        _setMinter(_minter);
    }

    // adds the minter to the array of minters[]
    function _setMinter(address _minter) internal {
        require(_minter != address(0), "SoulPower: cannot set minter to address(0)");
        minters.push(_minter);
    }

    // sets vault address
    function setVault(address _vault) external onlySupreme {
        _setVault(_vault);
    }

    function _setVault(address _vault) internal {
        require(_vault != address(0), "SoulPower: cannot set vault to address(0)");
        vaults.push(_vault);
    }

    // no time delay revoke minter (emergency function)
    function revokeMinter(address _minter) external onlySupreme {
        isMinter[_minter] = false;
    }

    // no time delay revoke vault (emergency function)
    function revokeVault(address _vault) external onlySupreme {
        isVault[_vault] = false;
    }

    // restrict: underlying to `_immutableUnderlying`
    function setImmutableUnderlying(address _immutableUnderlying) external onlySupreme {
        require(!isUnderlyingImmutable, 'underlying is already immutable');
        
        // sets: underlying address (permanent)
        underlying = _immutableUnderlying;
        
        // sets: underlying to immutable
        isUnderlyingImmutable = true;
    }

    function getAllMinters() external view returns (address[] memory) {
        return minters;
    }

    function getAllVaults() external view returns (address[] memory) {
        return vaults;
    }

    // mint: restricted to the role of Thoth.
    function mint(address to, uint amount) external obey(thoth) returns (bool) {
        _mint(to, amount);
        return true;
    }

    // burn: restricted to the role of Sophia.
    function burn(address from, uint amount) external obey(sophia) returns (bool) {
        _burn(from, amount);
        return true;
    }

    // thoth authorizes mint // transfer for `amount` of swapped in value to `account`
    function Swapin(bytes32 txhash, address account, uint amount) external obey(thoth) returns (bool) {
        if ( // [A] if the contract has enough (non-native) underlying (ERC20) to cover `amount`,
            underlying != address(0) &&
            IERC20(underlying).balanceOf(address(this)) >= amount
        ) { // then transfer requested `amount` of underlying (ERC20) to `account`.
            IERC20(underlying).safeTransfer(account, amount);
        } else { // [B] mint requested `amount` of SOUL to `account`.
            _mint(account, amount);
        }
        // logs Swapin event
        emit LogSwapin(txhash, account, amount);

        return true;
    }

    // authorizes user to swap out and burns swapped out tokens
    function Swapout(uint amount, address bindaddr) external returns (bool) {
        // checks for swapout restriction
        require(!_vaultOnly, "only the vault may swapout");
        require(bindaddr != address(0), "bindaddr cannot be address(0)");
    
        // if the underlying is non-native and the balance of the sender < `amount`
        if (underlying != address(0) && balanceOf[msg.sender] < amount) {
            // then transfer `amount` of underlying from the `msg.sender` to this contract.
            IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            _burn(msg.sender, amount);
        }
        emit LogSwapout(msg.sender, bindaddr, amount);
        return true;
    }

    /// @dev records # of SOUL that `account` (2nd) will be allowed to spend on behalf of another `account` (1st) via { transferFrom }.
    mapping(address => mapping(address => uint)) public override allowance;

    constructor() {
        name = 'SoulPower';
        symbol = 'SOUL';
        decimals = 18;
        underlying = address(0);

        supreme = msg.sender; // head supreme
        anunnaki = keccak256("anunnaki"); // alpha supreme
        thoth = keccak256("thoth"); // god of wisdom and magic
        sophia = keccak256("sophia"); // goddess of wisdom and magic

        // use init to allow for CREATE2 accross all chains
        _init = true;

        // toggles: swapout vs mint/burn
        _vaultOnly = false;
        _setVault(msg.sender);

        _divinationRitual(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, supreme); // supreme as root admin
        _divinationRitual(anunnaki, anunnaki, supreme); // anunnaki as admin of anunnaki
        _divinationRitual(thoth, anunnaki, supreme); // anunnaki as admin of thoth
        _divinationRitual(sophia, anunnaki, supreme); // anunnaki as admin of sophia

        _mint(supreme, 21_000 * 1e18); // mints initial supply of 21_000 SOUL
    }

    function totalSupply() external view override returns (uint) {
        return _totalSupply;
    }

    function newUnderlying(address _underlying) public obey(anunnaki) {
        require(!isUnderlyingImmutable, 'underlying is now immutable');
        underlying = _underlying;
    }

    // deposits: sender balance [receiver: sender]
    function deposit() external returns (uint) {
        uint _amount = IERC20(underlying).balanceOf(msg.sender);
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), _amount);
        return _deposit(_amount, msg.sender);
    }

    // deposits: `amount` from sender [receiver: sender]
    function deposit(uint amount) external returns (uint) {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        // deposits `amount`, then credits msg.sender as receiver.
        return _deposit(amount, msg.sender);
    }

    // deposits: `amount` from sender [receiver: `to`]
    function deposit(uint amount, address to) external returns (uint) {
        // sender transfers `amount` of underlying to this contract.
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        // deposits `amount`, then credits `to` as receiver of SOUL.
        return _deposit(amount, to);
    }

    // supreme-restricted withdrawal to enable toAddress-specification
    function depositVault(uint amount, address to) external onlySupreme returns (uint) {
        return _deposit(amount, to);
    }

    // mint `to` the requested `amount` of SOUL.
    function _deposit(uint amount, address to) internal returns (uint) {
        require(!underlyingIsMinted);
        require(_depositEnabled, 'deposits are disabled');

        require(underlying != address(0), 'cannot deposit native');
        require(underlying != address(this), 'cannot deposit SOUL');

        // mints `to` the requested `amount` of SOUL.
        _mint(to, amount);
        return amount;
    }

    // withdraws: balance from sender [receiver: sender]
    function withdraw() external returns (uint) {
        return _withdraw(msg.sender, balanceOf[msg.sender], msg.sender);
    }

    // withdraws: `amount` from sender [receiver: sender]
    function withdraw(uint amount) external returns (uint) {
        return _withdraw(msg.sender, amount, msg.sender);
    }

    // withdraws: `amount` from sender [receiver: `to`]
    function withdraw(uint amount, address to) external returns (uint) {
        return _withdraw(msg.sender, amount, to);
    }

    // supreme-restricted withdrawal to enable fromAddress-specification [receiver: `to`]
    function withdrawVault(address from, uint amount, address to) external onlySupreme returns (uint) {
        return _withdraw(from, amount, to);
    }

    // burns `amount` of SOUL `from` user, then transfers `to` the `amount` of underlying.
    function _withdraw(address from, uint amount, address to) internal returns (uint) {
        require(!underlyingIsMinted);
        require(_withdrawEnabled, 'withdrawals are disabled');

        // cannot withdraw when underlying is native.
        require(underlying != address(0), 'underlying cannot be native');
        // cannot withdraw when underlying is SOUL.
        require(underlying != address(this), 'underlying cannot be SOUL');

        // burns: SOUL belonging to `from` in the specified `amount`.
        _burn(from, amount);

        // transfers: `to` the underlying (ERC20) in the specified `amount`.
        IERC20(underlying).safeTransfer(to, amount);
        return amount;
    }

    // enables deposits and withdrawals
    function enableDeposits(bool enabled) external onlySupreme {
        _depositEnabled = enabled;
    }

    function enableWithdrawals(bool enabled) external onlySupreme {
        _withdrawEnabled = enabled;
    }

    // mints `amount` of SOUL to `account`
    function _mint(address account, uint amount) internal {
        require(account != address(0), "cannot mint to the zero address");

        // increases: totalSupply by `amount`
        _totalSupply += amount;

        // increases: user balance by `amount`
        balanceOf[account] += amount;

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint amount) internal {
        require(account != address(0), "cannot burn from the zero address");

        // checks: `account` balance to ensure coverage for burn `amount` [C].
        uint balance = balanceOf[account];
        require(balance >= amount, "burn amount exceeds balance");

        // reduces: `account` by `amount` [E1].
        balanceOf[account] = balance - amount;

        // reduces: totalSupply by `amount` [E2].
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function approve(address spender, uint value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);

        return true;
    }

    function transfer(address to, uint value) external override returns (bool) {
        require(to != address(0) && to != address(this));
        uint balance = balanceOf[msg.sender];
        require(balance >= value, "SoulPower: transfer amount exceeds balance");

        balanceOf[msg.sender] = balance - value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);

        return true;
    }

    function transferFrom(address from, address to, uint value) external override returns (bool) {
        require(to != address(0) && to != address(this));
        if (from != msg.sender) {
            uint allowed = allowance[from][msg.sender];
            if (allowed != type(uint).max) {
                require(
                    allowed >= value,
                    "SoulPower: request exceeds allowance"
                );
                uint reduced = allowed - value;
                allowance[from][msg.sender] = reduced;
                emit Approval(from, msg.sender, reduced);
            }
        }

        uint balance = balanceOf[from];
        require(balance >= value, "SoulPower: transfer amount exceeds balance");

        balanceOf[from] = balance - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);

        return true;
    }

    // grants `role` to `newAccount` && renounces `role` from `oldAccount` [ obey(role) ]
    function rethroneRitual(bytes32 role, address oldAccount, address newAccount) public obey(role) {
        require(oldAccount != newAccount, "must be a new address");
        grantRole(role, newAccount); // grants new account
        renounceRole(role, oldAccount); //  removes old account of role

        emit Rethroned(role, oldAccount, newAccount);
    }

    // solidifies roles (internal)
    function _divinationRitual(bytes32 _role, bytes32 _adminRole, address _account) internal {
        _setupRole(_role, _account);
        _setRoleAdmin(_role, _adminRole);
    }

    // updates supreme address (public anunnaki)
    function newSupreme(address _supreme) public obey(anunnaki) {
        require(supreme != _supreme, "make a change, be the change"); //  prevents self-destruct
        rethroneRitual(DEFAULT_ADMIN_ROLE, supreme, _supreme); //   empowers new supreme
        supreme = _supreme;

        emit NewSupreme(supreme);
    }

    // acquires chainID
    function getChainId() internal view returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}
