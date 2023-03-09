// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ICurve} from "../bonding-curves/ICurve.sol";
import {CurveErrorCodes} from "../bonding-curves/CurveErrorCodes.sol";

contract MockCurve is ICurve, CurveErrorCodes {
    bool buyErrorOn;
    Error buyError;
    bool sellErrorOn;
    Error sellError;

    function setBuyError(uint256 errorType) external {
        buyErrorOn = true;
        buyError = Error(errorType);
    }

    function setSellError(uint256 errorType) external {
        sellErrorOn = true;
        sellError = Error(errorType);
    }

    /**
     * @dev See {ICurve-validateDelta}
     */
    function validateDelta(uint128 /*delta*/ ) external pure override returns (bool valid) {
        // For a linear curve, all values of delta are valid
        return true;
    }

    /**
     * @dev See {ICurve-validateSpotPrice}
     */
    function validateSpotPrice(uint128 /* newSpotPrice */ ) external pure override returns (bool) {
        // For a linear curve, all values of spot price are valid
        return true;
    }

    /**
     * @dev See {ICurve-getBuyInfo}
     */

    function getBuyInfo(
        uint128 spotPrice,
        uint128 delta,
        uint256 numItems,
        uint256 feeMultiplier,
        uint256 protocolFeeMultiplier
    )
        external
        view
        override
        returns (
            Error error,
            uint128 newSpotPrice,
            uint128 newDelta,
            uint256 inputValue,
            uint256 tradeFee,
            uint256 protocolFee
        )
    {
        if (buyErrorOn) {
            return (buyError, spotPrice, delta, 10, 5, 1);
        }
        return (Error.OK, spotPrice, delta, 10, 5, 1);
    }

    /**
     * @dev See {ICurve-getSellInfo}
     */
    function getSellInfo(
        uint128 spotPrice,
        uint128 delta,
        uint256 numItems,
        uint256 feeMultiplier,
        uint256 protocolFeeMultiplier
    )
        external
        view
        override
        returns (
            Error error,
            uint128 newSpotPrice,
            uint128 newDelta,
            uint256 outputValue,
            uint256 tradeFee,
            uint256 protocolFee
        )
    {
        if (sellErrorOn) {
            return (sellError, spotPrice, delta, 10, 5, 1);
        }
        return (Error.OK, spotPrice, delta, 10, 5, 1);
    }
}
