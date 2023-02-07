// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Configurable} from "./Configurable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {XykCurve} from "../../bonding-curves/XykCurve.sol";
import {LSSVMPair} from "../../LSSVMPair.sol";

abstract contract UsingXykCurve is Configurable {
    function setupCurve() public override returns (ICurve) {
        return new XykCurve();
    }

    function modifyDelta(uint64) public pure override returns (uint64) {
        // @dev hard coded because it's used in some implementation specific tests, yes this is gross, sorry
        return 11;
    }

    function modifyDelta(uint64 delta, uint8 numItems) public pure override returns (uint64) {
        if (numItems >= delta) {
          return uint64(numItems) + 1;
        }
        else {
          return delta;
        }
    }

    function modifySpotPrice(uint56 /*spotPrice*/ ) public pure override returns (uint56) {
        return 0.01 ether;
    }

    function getParamsForPartialFillTest() public pure override returns (uint128 spotPrice, uint128 delta) {
        return (0.01 ether, 11);
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
            // Multiply token reserves by multiplier, divide by base for both spot price and delta
            spotPrice = uint128((pair.spotPrice() * percentage) / 1e18);
        } else {
            // Multiply token reserves by base, divide by multiplier for both spot price and delta
            spotPrice = uint128((pair.spotPrice() / 1e18) * percentage);
        }
    }
}
