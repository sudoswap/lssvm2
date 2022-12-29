// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IOwnershipTransferReceiver} from "../lib/IOwnershipTransferReceiver.sol";

contract TestPairManager2 is IOwnershipTransferReceiver {
    
    uint256 public value;

    constructor() {}

    function onOwnershipTransferred(address, bytes memory b) payable public {
        value = abi.decode(b, (uint256));
    }
}
