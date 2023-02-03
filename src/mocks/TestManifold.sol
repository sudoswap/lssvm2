// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import {IManifold} from "manifoldxyz/specs/IManifold.sol";

contract TestManifold is IManifold {
    address payable[] receivers;
    uint256[] bps;

    constructor(address payable[] memory _receivers, uint256[] memory _bps) {
        receivers = _receivers;
        bps = _bps;
    }

    function getRoyalties(uint256) external view returns (address payable[] memory, uint256[] memory) {
        return (receivers, bps);
    }
}
