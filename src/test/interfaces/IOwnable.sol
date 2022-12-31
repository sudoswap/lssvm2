// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOwnable {
  function transferOwnership(address newOwner) external;
  function owner() external returns(address);
}