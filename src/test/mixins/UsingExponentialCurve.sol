// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Configurable} from "./Configurable.sol";
import {LSSVMPair} from "../../LSSVMPair.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {ExponentialCurve} from "../../bonding-curves/ExponentialCurve.sol";

abstract contract UsingExponentialCurve is Configurable {
    function setupCurve() public override returns (ICurve) {
        return new ExponentialCurve();
    }

    function modifyDelta(uint128 delta) public pure override returns (uint128) {
        if (delta <= FixedPointMathLib.WAD) {
            // Ensure minimum multiplier of 0.001 wad
            return uint64(1001 * (FixedPointMathLib.WAD) / 1000);
        } else if (delta >= 11 * FixedPointMathLib.WAD / 10) {
            return uint64(11 * FixedPointMathLib.WAD / 10);
        } else {
            return delta;
        }
    }

    function modifyDelta(uint128 delta, uint8) public pure override returns (uint128) {
        if (delta <= FixedPointMathLib.WAD) {
            // Ensure minimum multiplier of 0.001 wad
            return uint64(1001 * (FixedPointMathLib.WAD) / 1000);
        } else if (delta >= 11 * FixedPointMathLib.WAD / 10) {
            return uint64(11 * FixedPointMathLib.WAD / 10);
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

    // Adjusts price up or down
    function getParamsForAdjustingPriceToBuy(LSSVMPair pair, uint256 percentage, bool isIncrease)
        public
        view
        override
        returns (uint128 spotPrice, uint128 delta)
    {
        delta = pair.delta();
        if (isIncrease) {
            // Multiply by multiplier, divide by base
            spotPrice = uint128((pair.spotPrice() * percentage) / 1e18);
        } else {
            // Multiply by base, divide by multiplier
            spotPrice = uint128((pair.spotPrice() / 1e18) * percentage);
        }
    }

    function getReasonableDeltaAndSpotPrice() public pure override returns (uint128 delta, uint128 spotPrice) {
        delta = 1.05e18;
        spotPrice = 1e18;
    }
}
