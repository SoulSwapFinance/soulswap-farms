// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/AccessControl.sol";

pragma solidity >=0.8.0;

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

// File: contracts/tokens/SeanceCircleV2.sol

pragma solidity >=0.8.0;

// SeanceCircle with Governance.
contract SeanceCircleV2 is IERC20, AccessControl {
    using SafeERC20 for IERC20;
    
    /// @dev stores key ERC20 details.
    string public name;
    string public symbol;
    uint8 public immutable override decimals;

    IERC20 public soul;

    /// @dev records amount of SEANCE owned by account.
    mapping(address => uint) public override balanceOf;
    uint private _totalSupply;

    // mapping used to verify minters (vanity).
    mapping(address => bool) public isMinter;
    
    // arrays composed of minters.
    address[] public minters;

    /// @dev records # of SEANCE that `account` (2nd) will be allowed to spend on behalf of another `account` (1st) via { transferFrom }.
    mapping(address => mapping(address => uint)) public override allowance;

    // supreme & roles
    address private supreme; // supreme divine
    bytes32 public anunnaki; // admin role
    bytes32 public thoth; // minter role
    bytes32 public sophia; // transfer/burner roles

    // events
    event NewSupreme(address supreme);
    event Rethroned(bytes32 role, address oldAccount, address newAccount);

    // modifiers
    modifier onlySupreme() {
        require(_msgSender() == supreme, 'sender must be supreme');
        _;
    }

    // restricted to the house of the role passed as an object to obey
    modifier obey(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    constructor() {
        // sets: key token details.
        name = 'SeanceCircle';
        symbol = 'SEANCE';
        decimals = 18;

        // sets: roles.
        supreme = msg.sender; // head supreme
        anunnaki = keccak256("anunnaki"); // alpha supreme
        thoth = keccak256("thoth"); // god of wisdom and magic
        sophia = keccak256("sophia"); // goddess of wisdom and magic

        // sets: SOUL token.
        soul = IERC20(0x11d6DD25c1695764e64F439E32cc7746f3945543);

        // divines: roles
        _divinationRitual(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, supreme); // supreme as root admin
        _divinationRitual(anunnaki, anunnaki, supreme); // anunnaki as admin of anunnaki
        _divinationRitual(thoth, anunnaki, supreme); // anunnaki as admin of thoth
        _divinationRitual(sophia, anunnaki, supreme); // anunnaki as admin of sophia

    }

    // mints: specified `amount` of SEANCE to `account` (thoth)
    function mint(address to, uint amount) external obey(thoth) returns (bool) {
        _mint(to, amount);
        return true;
    }

    // internal mint
    function _mint(address account, uint amount) internal {
        require(account != address(0), "cannot mint to the zero address");

        // increases: totalSupply by `amount`
        _totalSupply += amount;

        // increases: user balance by `amount`
        balanceOf[account] += amount;

        emit Transfer(address(0), account, amount);
    }


    // burns: destroys specified `amount` belonging to `from` (sophia)
    function burn(address from, uint amount) external obey(sophia) returns (bool) {
        _burn(from, amount);
        return true;
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

    // sets: total supply of SEANCE
    function totalSupply() external view override returns (uint) {
        return _totalSupply;
    }

    // sets: minter address (onlySupreme)
    function setMinter(address _minter) external onlySupreme {
        _setMinter(_minter);
    }

    // adds: the minter to the array of minters[]
    function _setMinter(address _minter) internal {
        require(_minter != address(0), "SeanceCircle: cannot set minter to address(0)");
        minters.push(_minter);
    }

    // no time delay revoke minter (onlySupreme)
    function revokeMinter(address _minter) external onlySupreme {
        isMinter[_minter] = false;
    }

    // approves: `spender` in the specified `amount`
    function approve(address spender, uint value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);

        return true;
    }

    // restricts: `transfer` (sophia)
    function transfer(address to, uint value) external override obey(sophia) returns (bool) {
        require(to != address(0) && to != address(this), 'SeanceCircle: cannot send to address(0) nor to SEANCE');
        uint senderBalance = balanceOf[msg.sender];
        require(senderBalance >= value, "SeanceCircle: transfer amount exceeds balance");

        balanceOf[msg.sender] = senderBalance - value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);

        return true;
    }

    // restricts: `transferFrom` (sophia)
    function transferFrom(address from, address to, uint value) external override obey(sophia) returns (bool) {
        require(to != address(0) && to != address(this));
        if (from != msg.sender) {
            uint allowed = allowance[from][msg.sender];
            if (allowed != type(uint).max) {
                require(
                    allowed >= value,
                    "SeanceCircle: request exceeds allowance"
                );
                uint reduced = allowed - value;
                allowance[from][msg.sender] = reduced;
                emit Approval(from, msg.sender, reduced);
            }
        }

        uint balance = balanceOf[from];
        require(balance >= value, "SeanceCircle: transfer amount exceeds balance");

        balanceOf[from] = balance - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);

        return true;
    }

    // grants: `role` to `newAccount` && renounces `role` from `oldAccount` [ obey(role) ]
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

    // updates supreme address (anunnaki).
    function newSupreme(address _supreme) external obey(anunnaki) {
        require(supreme != _supreme, "make a change, be the change"); //  prevents self-destruct
        rethroneRitual(DEFAULT_ADMIN_ROLE, supreme, _supreme); //   empowers new supreme
        supreme = _supreme;

        emit NewSupreme(supreme);
    }

    // prevents: sending partial SOUL rewards.
    function safeSoulTransfer(address to, uint amount) external obey(sophia) {
        uint soulBal = soul.balanceOf(address(this));
        require(amount <= soulBal, 'amount exceeds balance');
        soul.transfer(to, amount);
    }

    // shows: chainId (view)
    function getChainId() external view returns (uint chainId) {
        assembly { chainId := chainid() }
        return chainId;
    }

    // updates: address for SOUL (onlySupreme).
    function newSoul(address _soul) external onlySupreme {
        require(soul != IERC20(_soul), 'must be a new address');
        soul = IERC20(_soul);
    }

}