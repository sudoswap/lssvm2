// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IOwnershipTransferCallback} from "../lib/IOwnershipTransferCallback.sol";

contract TestPairManager2 is IOwnershipTransferCallback {
    
    uint256 public value;

    constructor() {}

    function onOwnershipTransfer(address, bytes memory b) payable public {
        value = abi.decode(b, (uint256));
    }
}
