// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LSSVMPair} from "../LSSVMPair.sol";
import {IOwnershipTransferReceiver} from "../lib/IOwnershipTransferReceiver.sol";

contract MockOwnershipTransferReceiver is IOwnershipTransferReceiver {
    // Fake callback function that in theory would allow a malicious actor to do anything
    // to the pair during a multicall and return ownership at the end of the txn.
    function onOwnershipTransferred(address prevOwner, bytes memory) public payable {
        LSSVMPair pair = LSSVMPair(msg.sender);

        // Run malicious code
        pair.changeAssetRecipient(payable(address(this)));

        // Transfer back to the original owner
        pair.transferOwnership(prevOwner, "");
    }
}
