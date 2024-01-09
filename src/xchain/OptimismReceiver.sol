// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LibOptimism} from "@openzeppelin/contracts/crosschain/optimism/LibOptimism.sol";

contract OptimismReceiver {

    error OptimismReceiver__NotGov();
    error OptimismReceiver__CallFail();

    address immutable public governorAddress;

    constructor(address _governorAddress) {
        governorAddress = _governorAddress;
    }

    function execute(address target, uint256 value, bytes calldata data) external {
        address l1Sender = LibOptimism.crossChainSender(msg.sender);
        if (l1Sender != governorAddress) {
            revert OptimismReceiver__NotGov();
        }
        (bool success,) = target.call{value: value}(data);
        if (! success) {
            revert OptimismReceiver__CallFail();
        }
    }
}