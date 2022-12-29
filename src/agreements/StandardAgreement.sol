// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IOwnershipTransferReceiver} from "../lib/IOwnershipTransferReceiver.sol";
import {OwnableWithTransferCallback} from "../lib/OwnableWithTransferCallback.sol";

contract StandardAgreement is
    IOwnershipTransferReceiver,
    OwnableWithTransferCallback
{
    /**
      - cost
      - duration
      - split
      - owner
     */

    function onOwnershipTransferred(address prevOwner, bytes memory)
        public
        payable
    {}
}
