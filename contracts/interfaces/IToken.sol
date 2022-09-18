// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// interface used for interacting with SOUL & SEANCE
interface IToken {
    function mint(address to, uint amount) external;
    function burn(address from, uint amount) external;
    function safeSoulTransfer(address to, uint amount) external;
    function balanceOf(address account) external returns (uint balance);
}