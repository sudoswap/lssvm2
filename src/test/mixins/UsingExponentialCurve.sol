// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Configurable} from "./Configurable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {ExponentialCurve} from "../../bonding-curves/ExponentialCurve.sol";

abstract contract UsingExponentialCurve is Configurable {
    function setupCurve() public override returns (ICurve) {
        return new ExponentialCurve();
    }

    function modifyDelta(uint64 delta) public pure override returns (uint64) {
        uint64 ZERO_SHIFT_AMOUNT = 10000000;
        if (delta <= FixedPointMathLib.WAD) {
            // Zero out last few decimals
            delta = delta / ZERO_SHIFT_AMOUNT;
            delta = delta * ZERO_SHIFT_AMOUNT;
            // Ensure minimum multiplier of 0.001 wad
            return uint64(1001 * (FixedPointMathLib.WAD + delta) / 1000);
        } else if (delta >= 2 * FixedPointMathLib.WAD) {
            return uint64(2 * FixedPointMathLib.WAD);
        } else {
            return delta;
        }
    }

    function modifySpotPrice(uint56 spotPrice) public pure override returns (uint56) {
        uint56 ZERO_SHIFT_AMOUNT = 10000;
        // Zero out last few decimals
        spotPrice = spotPrice / ZERO_SHIFT_AMOUNT;
        spotPrice = spotPrice * ZERO_SHIFT_AMOUNT;
        if (spotPrice < 1 gwei) {
            return 1 gwei;
        } else {
            return spotPrice;
        }
    }

    // Return 1 eth as spot price and 10% as the delta scaling
    function getParamsForPartialFillTest() public pure override returns (uint128 spotPrice, uint128 delta) {
        return (10 ** 18, 1.1 * (10 ** 18));
    }
}
