// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

contract MockL2System {
    
    error MockL2System__NotOwner();

    address immutable owner;
    uint256 public count;

    constructor(address _owner) {
        owner = _owner;
    }

    function inc(uint256 amt) public {
        if (msg.sender != owner) {
            revert MockL2System__NotOwner();
        }
        count += amt;
    }
}