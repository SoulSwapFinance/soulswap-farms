// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @dev Interface of the ERC2612 standard as defined in the EIP.
 *
 * Adds the {permit} method, which can be used to change one's
 * {IERC20-allowance} without having to send a transaction, by signing a
 * message. This allows users to spend tokens without having to hold Ether.
 *
 * See https://eips.ethereum.org/EIPS/eip-2612.
 */
interface IERC2612 {
    /**
     * @dev Sets `amount` as the allowance of `spender` over `owner`'s tokens,
     * given `owner`'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current ERC2612 nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);
}

library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

interface ITransferReceiver {
    function onTokenTransfer(
        address,
        uint256,
        bytes calldata
    ) external returns (bool);
}

interface IApprovalReceiver {
    function onTokenApproval(
        address,
        uint256,
        bytes calldata
    ) external returns (bool);
}

contract SoulPowerMulti is IERC20, IERC2612, AccessControl {
    using SafeERC20 for IERC20;
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint value,uint nonce,uint deadline)"
        );
    bytes32 public constant TRANSFER_TYPEHASH =
        keccak256(
            "Transfer(address owner,address to,uint value,uint nonce,uint deadline)"
        );
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @dev Records amount of WERC10 token owned by account.
    mapping(address => uint) public override balanceOf;
    uint private _totalSupply;

    address private _oldOwner;
    address private _newOwner;
    uint private _newOwnerEffectiveTime;

    address public supreme; // supreme divine
    bytes32 public anunnaki; // admin role
    bytes32 public thoth; // minter role
    bytes32 public sophia; // burner role

    function owner() public view returns (address) {
        if (block.timestamp >= _newOwnerEffectiveTime) {
            return _newOwner;
        }
        return _oldOwner;
    }

    /// @dev Records current ERC2612 nonce for account. This value must be included whenever signature is generated for {permit}.
    /// Every successful call to {permit} increases account's nonce by one. This prevents signature from being used multiple times.
    mapping(address => uint) public override nonces;

    /// @dev Records number of WERC10 token that account (second) will be allowed to spend on behalf of another account (first) through {transferFrom}.
    mapping(address => mapping(address => uint)) public override allowance;

    // for multichain compatibility, adopted from https://docs.multichain.org/developer-guide/how-to-develop-under-anyswap-erc20-standards
    address public immutable underlying = address(0);

    event LogChangeDCRMOwner(
        address indexed oldOwner,
        address indexed newOwner,
        uint indexed effectiveTime
    );
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
    event NewSupreme(address supreme);
    event Rethroned(bytes32 role, address oldAccount, address newAccount);

    // channels the authority vested in anunnaki, thoth, and sophia to the supreme
    constructor() {
        name = "SoulPower"; // name
        symbol = "SOUL"; // symbol
        decimals = 18; // decimals

        _newOwner = msg.sender;
        _newOwnerEffectiveTime = block.timestamp;

        supreme = msg.sender; // head supreme
        anunnaki = keccak256("anunnaki"); // alpha supreme
        thoth = keccak256("thoth"); // god of wisdom and magic
        sophia = keccak256("sophia"); // goddess of wisdom and magic

        _divinationRitual(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, supreme); // supreme as root admin
        _divinationRitual(anunnaki, anunnaki, supreme); // anunnaki as admin of anunnaki
        _divinationRitual(thoth, anunnaki, supreme); // anunnaki as admin of thoth
        _divinationRitual(sophia, anunnaki, supreme); // anunnaki as admin of sophia

        _mint(supreme, 21_000 * 1e18); // mints initial supply of 21_000 SOUL

        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    // restricted to the house of the role passed as an object to obey
    modifier obey(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    // solidifies roles (internal)
    function _divinationRitual(
        bytes32 _role,
        bytes32 _adminRole,
        address _account
    ) internal {
        _setupRole(_role, _account);
        _setRoleAdmin(_role, _adminRole);
    }

    // grants `role` to `newAccount` && renounces `role` from `oldAccount` (public role)
    function rethroneRitual(
        bytes32 role,
        address oldAccount,
        address newAccount
    ) public obey(role) {
        require(oldAccount != newAccount, "must be a new address");
        grantRole(role, newAccount); // grants new account
        renounceRole(role, oldAccount); //  removes old account of role

        emit Rethroned(role, oldAccount, newAccount);
    }

    // updates supreme address (public anunnaki)
    function newSupreme(address _supreme) public obey(anunnaki) {
        require(supreme != _supreme, "make a change, be the change"); //  prevents self-destruct
        rethroneRitual(DEFAULT_ADMIN_ROLE, supreme, _supreme); //   empowers new supreme
        supreme = _supreme;

        emit NewSupreme(supreme);
    }

    // checks whether sender has divine role (public view)
    function hasDivineRole(bytes32 role) public view returns (bool) {
        return hasRole(role, msg.sender);
    }

    /// @dev Returns the total supply of WERC10 token as the ETH held in this contract.
    function totalSupply() external view override returns (uint) {
        return _totalSupply;
    }

    function changeDCRMOwner(address newOwner) public obey(thoth) returns (bool) {
        require(newOwner != address(0), "new owner is the zero address");
        _oldOwner = owner();
        _newOwner = newOwner;
        _newOwnerEffectiveTime = block.timestamp + 2 * 24 * 3600;
        emit LogChangeDCRMOwner(_oldOwner, _newOwner, _newOwnerEffectiveTime);
        return true;
    }

    function Swapin(
        bytes32 txhash,
        address account,
        uint amount
    ) public obey(thoth) returns (bool) {
        _mint(account, amount);
        emit LogSwapin(txhash, account, amount);
        return true;
    }

    function Swapout(uint amount, address bindaddr) public returns (bool) {
        require(bindaddr != address(0), "bind address is the zero address");
        _burn(msg.sender, amount);
        emit LogSwapout(msg.sender, bindaddr, amount);
        return true;
    }

    // mints soul power as the house of thoth so wills (public thoth) (bridge-compatible)
    function mint(address _to, uint _amount) external obey(thoth) returns (bool) {
        _mint(_to, _amount);
        return true;
    }

    // internal mint function (cannot be to the 0 address)
    function _mint(address to, uint amount) internal {
        require(to != address(0), '_minting to the zero address (0x0)');

        _totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(uint amount) external obey(sophia) returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }

    function burn(address from, uint amount) external obey(sophia) returns (bool) {
        require(from != address(0), "burning from the zero address (0x0)");
        _burn(from, amount);
        return true;
    }

    /// @dev Sets `value` as allowance of `spender` account over caller account's WERC10 token.
    function approve(address spender, uint value)
        external
        override
        returns (bool)
    {
        // _approve(msg.sender, spender, value);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);

        return true;
    }

    // destroys `amount` tokens from the `account` (public)
    function burnFrom(address account, uint amount) public {
        uint currentAllowance = allowance[account][msg.sender];
        require(currentAllowance >= amount, "burn amount exceeds allowance");
        allowance[account][msg.sender] = currentAllowance - amount;
        _burn(account, amount);
    }

    // internal burn function
    function _burn(address account, uint amount) internal {
        require(account != address(0), "should not _burn from the zero address (0x0)");

        balanceOf[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    /// @dev Sets `value` as allowance of `spender` account over caller account's WERC10 token,
    /// after which a call is executed to an ERC677-compliant contract with the `data` parameter.
    /// Emits {Approval} event.
    /// Returns boolean value indicating whether operation succeeded.
    /// For more information on approveAndCall format, see https://github.com/ethereum/EIPs/issues/677.
    function approveAndCall(
        address spender,
        uint value,
        bytes calldata data
    ) external returns (bool) {
        // _approve(msg.sender, spender, value);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);

        return
            IApprovalReceiver(spender).onTokenApproval(msg.sender, value, data);
    }

    /// @dev Sets `value` as allowance of `spender` account over `owner` account's WERC10 token, given `owner` account's signed approval.
    /// Emits {Approval} event.
    /// Requirements:
    ///   - `deadline` must be timestamp in future.
    ///   - `v`, `r` and `s` must be valid `secp256k1` signature from `owner` account over EIP712-formatted function arguments.
    ///   - the signature must use `owner` account's current nonce (see {nonces}).
    ///   - the signer cannot be zero address and must be `owner` account.
    /// For more information on signature format, see https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP section].
    /// WERC10 token implementation adapted from https://github.com/albertocuestacanada/ERC20Permit/blob/master/contracts/ERC20Permit.sol.
    function permit(
        address target,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(block.timestamp <= deadline, "WERC10: Expired permit");

        bytes32 hashStruct = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                target,
                spender,
                value,
                nonces[target]++,
                deadline
            )
        );

        require(
            verifyEIP712(target, hashStruct, v, r, s) ||
                verifyPersonalSign(target, hashStruct, v, r, s)
        );

        // _approve(owner, spender, value);
        allowance[target][spender] = value;
        emit Approval(target, spender, value);
    }

    function transferWithPermit(
        address target,
        address to,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool) {
        require(block.timestamp <= deadline, "WERC10: Expired permit");

        bytes32 hashStruct = keccak256(
            abi.encode(
                TRANSFER_TYPEHASH,
                target,
                to,
                value,
                nonces[target]++,
                deadline
            )
        );

        require(
            verifyEIP712(target, hashStruct, v, r, s) ||
                verifyPersonalSign(target, hashStruct, v, r, s)
        );

        require(to != address(0) || to != address(this));

        uint balance = balanceOf[target];
        require(balance >= value, "WERC10: transfer amount exceeds balance");

        balanceOf[target] = balance - value;
        balanceOf[to] += value;
        emit Transfer(target, to, value);

        return true;
    }

    function verifyEIP712(
        address target,
        bytes32 hashStruct,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (bool) {
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashStruct)
        );
        address signer = ecrecover(hash, v, r, s);
        return (signer != address(0) && signer == target);
    }

    function verifyPersonalSign(
        address target,
        bytes32 hashStruct,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bool) {
        bytes32 hash = prefixed(hashStruct);
        address signer = ecrecover(hash, v, r, s);
        return (signer != address(0) && signer == target);
    }

    // Builds a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    /// @dev Moves `value` WERC10 token from caller's account to account (`to`).
    /// A transfer to `address(0)` triggers an ETH withdraw matching the sent WERC10 token in favor of caller.
    /// Emits {Transfer} event.
    /// Returns boolean value indicating whether operation succeeded.
    /// Requirements:
    ///   - caller account must have at least `value` WERC10 token.
    function transfer(address to, uint value)
        external
        override
        returns (bool)
    {
        require(to != address(0) || to != address(this));
        uint balance = balanceOf[msg.sender];
        require(balance >= value, "WERC10: transfer amount exceeds balance");

        balanceOf[msg.sender] = balance - value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);

        return true;
    }

    /// @dev Moves `value` WERC10 token from account (`from`) to account (`to`) using allowance mechanism.
    /// `value` is then deducted from caller account's allowance, unless set to `type(uint).max`.
    /// A transfer to `address(0)` triggers an ETH withdraw matching the sent WERC10 token in favor of caller.
    /// Emits {Approval} event to reflect reduced allowance `value` for caller account to spend from account (`from`),
    /// unless allowance is set to `type(uint).max`
    /// Emits {Transfer} event.
    /// Returns boolean value indicating whether operation succeeded.
    /// Requirements:
    ///   - `from` account must have at least `value` balance of WERC10 token.
    ///   - `from` account must have approved caller to spend at least `value` of WERC10 token, unless `from` and caller are the same account.
    function transferFrom(
        address from,
        address to,
        uint value
    ) external override returns (bool) {
        require(to != address(0) || to != address(this));
        if (from != msg.sender) {
            // _decreaseAllowance(from, msg.sender, value);
            uint allowed = allowance[from][msg.sender];
            if (allowed != type(uint).max) {
                require(allowed >= value, "WERC10: request exceeds allowance");
                uint reduced = allowed - value;
                allowance[from][msg.sender] = reduced;
                emit Approval(from, msg.sender, reduced);
            }
        }

        uint balance = balanceOf[from];
        require(balance >= value, "WERC10: transfer amount exceeds balance");

        balanceOf[from] = balance - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);

        return true;
    }

    function transferAndCall(
        address to,
        uint value,
        bytes calldata data
    ) external returns (bool) {
        require(to != address(0) || to != address(this));

        uint balance = balanceOf[msg.sender];
        require(balance >= value, "transfer amount exceeds balance");

        balanceOf[msg.sender] = balance - value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);

        return ITransferReceiver(to).onTokenTransfer(msg.sender, value, data);
    }

    // acquires chainID
    function getChainId() internal view returns (uint) {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
