// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Configurable} from "./Configurable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LinearCurve} from "../../bonding-curves/LinearCurve.sol";

abstract contract UsingLinearCurve is Configurable {
    function setupCurve() public override returns (ICurve) {
        return new LinearCurve();
    }

    function modifyDelta(uint64 delta) public pure override returns (uint64) {
        return delta;
    }

    function modifySpotPrice(uint56 spotPrice) public pure override returns (uint56) {
        return spotPrice;
    }

    // Return 1 eth as spot price and 0.1 eth as the delta scaling
    function getParamsForPartialFillTest() public pure override returns (uint128 spotPrice, uint128 delta) {
        return (10 ** 18, 10 ** 17);
    }
}
