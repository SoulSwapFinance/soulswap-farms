// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";

// --------------------------------------------------------------------------------------
//  Allows multiple contracts to act as `owner`, from `Ownable.sol`, with `onlyOperator`.
// --------------------------------------------------------------------------------------

abstract contract Operable is Context, Ownable {

    address[] public operators;
    mapping(address => bool) public operator;

    event OperatorUpdated(address indexed operator, bool indexed access);
    constructor () {
        address msgSender = _msgSender();
        operator[msgSender] = true;
        operators.push(msgSender);
        emit OperatorUpdated(msgSender, true);
    }

    /**
     * @dev Throws if called by any account other than the operator.
     */
    modifier onlyOperator() {
        address msgSender = _msgSender();
        require(operator[msgSender], "Operator: caller is not an operator");
        _;
    }

    /**
     * @dev Leaves the contract without operator. It will not be possible to call
     * `onlyOperator` functions anymore. Can only be called by an operator.
     */
    function removeOperator(address removingOperator) public virtual onlyOperator {
        require(operator[removingOperator], 'Operable: address is not an operator');
        operator[removingOperator] = false;
        for (uint8 i; i < operators.length; i++) {
            if (operators[i] == removingOperator) {
                operators[i] = operators[i+1];
                operators.pop();
                emit OperatorUpdated(removingOperator, false);
                return;
            }
        }
    }

    /**
     * @dev Adds address as operator of the contract.
     * Can only be called by an operator.
     */
    function addOperator(address newOperator) public virtual onlyOperator {
        require(newOperator != address(0), "Operable: new operator is the zero address");
        require(!operator[newOperator], 'Operable: address is already an operator');
        operator[newOperator] = true;
        operators.push(newOperator);
        emit OperatorUpdated(newOperator, true);
    }
}