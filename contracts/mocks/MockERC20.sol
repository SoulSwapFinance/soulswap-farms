// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/ERC20.sol";

contract MockERC20 is ERC20, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) ERC20(name, symbol) {
        _mint(msg.sender, supply * 1E18);
    }

    function mint(uint amount) external onlyOwner {
        _mint(msg.sender, amount);
    }
}
