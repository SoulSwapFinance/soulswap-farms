pragma solidity ^0.8.0;

import './libraries/ERC20.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

// --------------------------------------------------------------------------------------
//
// (c) SoulPower 06/08/2021 | SPDX-License-Identifier: MIT
// Designed by, 0xBuns + DeGatchi.
// 
// --------------------------------------------------------------------------------------

contract SoulPower is ERC20('SoulPower', 'SOUL'), AccessControl {
    // multi-sig admin
    address public admin;

    // divine roles
    bytes32 public anunnaki; // admin role
    bytes32 public thoth;   // minter role

    event NewAdmin(address admin);
    event Rethroned(bytes3 role, address oldAccount, address newAccount);

    // restricted to the council of the role passed as an object to obey (role)
    modifier obey(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    // channels the power of the anunnaki and thoth to the admin (admin)
    constructor(address _admin) {
        admin = _admin;
        anunnaki = keccak256('anunnaki'); // alpha supreme
        thoth = keccak256('thoth');      // god of wisdom and magic

        _divinationRitual(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, admin); // sets admin as default-admin (root)
        _divinationRitual(anunnaki, anunnaki, admin);                    // sets anunnaki as self-admin
        _divinationRitual(thoth, anunnaki, admin);                      // sets anunnaki as admin of thoth
    }

    // solidifies roles (internal)
    function _divinationRitual(bytes32 _role, bytes32 _adminRole, address _account) internal {
        _setupRole(_role, _account);
        _setRoleAdmin(_role, _adminRole);
    }

    // grants `role` to `newAccount` && renounces `role` from `oldAccount`
    function rethroneRitual(
        bytes32 role,               //  updated role
        address oldAccount,        //   renounces role
        address newAccount        //    thrones role
    ) public obey(role) {
        require(oldAccount != newAccount, 'must be a new address');
        grantRole(role, newAccount);     // grants new account
        renounceRole(role, oldAccount); //  removes old account of role
    }

    // updates admin address
    function newAdmin(address _admin) public obey(anunnaki) {
        require(admin != _admin, 'make a change, be the change');  //  prevents self-destruct
        rethroneRitual(DEFAULT_ADMIN_ROLE, admin, _admin);        //   empowers new supreme
        admin = _admin;

        emit NewAdmin(admin);
    }

    // checks whether sender has divine role (view)
    function hasDivineRole(bytes32 role) public view returns (bool) {
        return hasRole(role, msg.sender);
    }

    // mints soul power as the council of thoth so wills
    function mint(address _to, uint256 _amount) public obey(thoth) {
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
    }

    // destroys `amount` tokens from the caller (public sender, token holder)
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
        _moveDelegates(_delegates[_msgSender()], address(0), amount);
    }

    // destroys `amount` tokens from the `account` (public sender, with allowance)
    function burnFrom(address account, uint256 amount) public {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, 'ERC20: burn amount exceeds allowance');

        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
        _moveDelegates(_delegates[account], address(0), amount);
    }

    // record of each accounts' delegate
    mapping(address => address) internal _delegates;

    // checkpoint for marking number of votes from a given timestamp
    struct Checkpoint {
        uint256 fromTime;
        uint256 votes;
    }

    // record of votes checkpoints for each account, by index
    mapping(address => mapping(uint256 => Checkpoint)) public checkpoints;

    // number of checkpoints for each account
    mapping(address => uint256) public numCheckpoints;

    // EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256('EIP712Domain(string name,uint chainId,address verifyingContract)');

    // EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256('Delegation(address delegatee,uint nonce,uint expiry)');

    // record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    // emitted when an account changes its delegate
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    // emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    // returns the address delegated by a given delegator
    function delegates(address delegator) external view returns (address) {
        return _delegates[delegator];
    }

    // delegates to the `delegatee` (external sender)
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    // delegates votes from signatory to `delegatee` (external)
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this))
        );

        bytes32 structHash = keccak256(
            abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)
        );

        bytes32 digest = keccak256(
            abi.encodePacked('\x19\x01', domainSeparator, structHash)
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), 'delegateBySig: invalid signature');
        require(nonce == nonces[signatory]++, 'delegateBySig: invalid nonce');
        require(block.timestamp <= expiry, 'delegateBySig: signature expired');
        return _delegate(signatory, delegatee);
    }

    // returns current votes balance for `account`
    function getCurrentVotes(address account) external view returns (uint256) {
        uint256 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    // returns an account's prior vote count as of a given timestamp
    function getPriorVotes(address account, uint256 blockTimestamp) external view returns (uint256) {
        require(blockTimestamp < block.timestamp, 'getPriorVotes: not yet determined');
        
        uint256 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) { return 0; }

        // checks most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromTime <= blockTimestamp) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // next checks implicit zero balance
        if (checkpoints[account][0].fromTime > blockTimestamp) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromTime == blockTimestamp) {
                return cp.votes;
            } else if (cp.fromTime < blockTimestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }

        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying SOUL (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);
        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decreases old representative
                uint256 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0
                    ? checkpoints[srcRep][srcRepNum - 1].votes
                    : 0;
                uint256 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increases new representative
                uint256 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0
                    ? checkpoints[dstRep][dstRepNum - 1].votes
                    : 0;
                uint256 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint256 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        uint256 blockTimestamp = safe256(block.timestamp, 'block timestamp exceeds 256 bits');

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromTime == blockTimestamp) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else { 
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockTimestamp, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe256(uint256 n, string memory errorMessage) internal pure returns (uint256) {
        require(n < type(uint256).max, errorMessage);
        return uint256(n);
    }

    // returns chainId
    function getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}
