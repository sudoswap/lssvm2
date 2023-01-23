// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IOwnershipTransferReceiver} from "../lib/IOwnershipTransferReceiver.sol";

contract TestPairManager is IOwnershipTransferReceiver {
    address public prevOwner;

    constructor() {}

    function onOwnershipTransferred(address a, bytes memory) public payable {
        prevOwner = a;
    }
}
