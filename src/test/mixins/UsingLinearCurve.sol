// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Configurable} from "./Configurable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LSSVMPair} from "../../LSSVMPair.sol";
import {LinearCurve} from "../../bonding-curves/LinearCurve.sol";

abstract contract UsingLinearCurve is Configurable {
    function setupCurve() public override returns (ICurve) {
        return new LinearCurve();
    }

    function modifyDelta(uint64 delta) public pure override returns (uint64) {
        return delta;
    }

    function modifyDelta(uint64 delta, uint8) public pure override returns (uint64) {
        return delta;
    }

    function modifySpotPrice(uint56 spotPrice) public pure override returns (uint56) {
        return spotPrice;
    }

    // Return 1 eth as spot price and 0.1 eth as the delta scaling
    function getParamsForPartialFillTest() public pure override returns (uint128 spotPrice, uint128 delta) {
        return (10 ** 18, 10 ** 17);
    }

    // Adjusts price up or down
    function getParamsForAdjustingPriceToBuy(LSSVMPair pair, uint256 percentage, bool isIncrease)
        public
        view
        override
        returns (uint128 spotPrice, uint128 delta)
    {
        if (isIncrease) {
            // Multiply by multiplier, divide by base for both spot price and delta
            spotPrice = uint128((pair.spotPrice() * percentage) / 1e18);
            delta = uint128((pair.delta() * percentage) / 1e18);
        } else {
            // Multiply by base, divide by multiplier for both spot price and delta
            spotPrice = uint128((pair.spotPrice() / 1e18) * percentage);
            delta = uint128((pair.delta() * 1e18) / percentage);
        }
    }

    function getReasonableDeltaAndSpotPrice() public pure override returns (uint128 delta, uint128 spotPrice) {
        delta = 0.01e18;
        spotPrice = 1e18;
    }
}
