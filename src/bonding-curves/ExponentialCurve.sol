// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ICurve} from "./ICurve.sol";
import {CurveErrorCodes} from "./CurveErrorCodes.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/*
    @author 0xmons and boredGenius
    @notice Bonding curve logic for an exponential curve, where each buy/sell changes spot price by multiplying/dividing delta*/
contract ExponentialCurve is ICurve, CurveErrorCodes {
    using FixedPointMathLib for uint256;

    /**
     * @dev See {ICurve-validateDelta}
     */
    function validateDelta(uint128 delta) external pure override returns (bool) {
        return delta > FixedPointMathLib.WAD;
    }

    /**
     * @dev See {ICurve-validateSpotPrice}
     */
    function validateSpotPrice(uint128) external pure override returns (bool) {
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
        pure
        override
        returns (Error error, uint128 newSpotPrice, uint128 newDelta, uint256 inputValue, uint256 protocolFee)
    {
        // NOTE: we assume delta is > 1, as checked by validateDelta()
        // We only calculate changes for buying 1 or more NFTs
        if (numItems == 0) {
            return (Error.INVALID_NUMITEMS, 0, 0, 0, 0);
        }

        uint256 deltaPowN = uint256(delta).rpow(numItems, FixedPointMathLib.WAD);

        // For an exponential curve, the spot price is multiplied by delta for each item bought
        uint256 newSpotPrice_ = uint256(spotPrice).mulWadUp(deltaPowN);
        if (newSpotPrice_ > type(uint128).max) {
            return (Error.SPOT_PRICE_OVERFLOW, 0, 0, 0, 0);
        }
        newSpotPrice = uint128(newSpotPrice_);

        // Spot price is assumed to be the instant sell price. To avoid arbitraging LPs, we adjust the buy price upwards.
        // If spot price for buy and sell were the same, then someone could buy 1 NFT and then sell for immediate profit.
        // EX: Let S be spot price. Then buying 1 NFT costs S ETH, now new spot price is (S * delta).
        // The same person could then sell for (S * delta) ETH, netting them delta ETH profit.
        // If spot price for buy and sell differ by delta, then buying costs (S * delta) ETH.
        // The new spot price would become (S * delta), so selling would also yield (S * delta) ETH.
        uint256 buySpotPrice = uint256(spotPrice).mulWadUp(delta);

        // If the user buys n items, then the total cost is equal to:
        // buySpotPrice + (delta * buySpotPrice) + (delta^2 * buySpotPrice) + ... (delta^(numItems - 1) * buySpotPrice)
        // This is equal to buySpotPrice * (delta^n - 1) / (delta - 1)
        inputValue =
            buySpotPrice.mulWadUp((deltaPowN - FixedPointMathLib.WAD).divWadUp(delta - FixedPointMathLib.WAD));

        // Account for the protocol fee, a flat percentage of the buy amount
        protocolFee = inputValue.mulWadUp(protocolFeeMultiplier);

        // Account for the trade fee, only for Trade pools
        inputValue += inputValue.mulWadUp(feeMultiplier);

        // Add the protocol fee to the required input amount
        inputValue += protocolFee;

        // Keep delta the same
        newDelta = delta;

        // If we got all the way here, no math error happened
        error = Error.OK;
    }

    /**
     * @dev See {ICurve-getSellInfo}
     *     If newSpotPrice is less than MIN_PRICE, newSpotPrice is set to MIN_PRICE instead.
     *     This is to prevent the spot price from ever becoming 0, which would decouple the price
     *     from the bonding curve (since 0 * delta is still 0)
     */
    function getSellInfo(
        uint128 spotPrice,
        uint128 delta,
        uint256 numItems,
        uint256 feeMultiplier,
        uint256 protocolFeeMultiplier
    )
        external
        pure
        override
        returns (Error error, uint128 newSpotPrice, uint128 newDelta, uint256 outputValue, uint256 protocolFee)
    {
        // NOTE: we assume delta is > 1, as checked by validateDelta()

        // We only calculate changes for buying 1 or more NFTs
        if (numItems == 0) {
            return (Error.INVALID_NUMITEMS, 0, 0, 0, 0);
        }

        uint256 invDelta = FixedPointMathLib.WAD.divWadDown(delta);
        uint256 invDeltaPowN = invDelta.rpow(numItems, FixedPointMathLib.WAD);

        // For an exponential curve, the spot price is divided by delta for each item sold
        // safe to convert newSpotPrice directly into uint128 since we know newSpotPrice <= spotPrice
        // and spotPrice <= type(uint128).max
        newSpotPrice = uint128(uint256(spotPrice).mulWadDown(invDeltaPowN));

        // If the user sells n items, then the total revenue is equal to:
        // spotPrice + ((1 / delta) * spotPrice) + ((1 / delta)^2 * spotPrice) + ... ((1 / delta)^(numItems - 1) * spotPrice)
        // This is equal to spotPrice * (1 - (1 / delta^n)) / (1 - (1 / delta))
        outputValue = uint256(spotPrice).mulWadDown(
            (FixedPointMathLib.WAD - invDeltaPowN).divWadDown(FixedPointMathLib.WAD - invDelta)
        );

        // Account for the protocol fee, a flat percentage of the sell amount
        protocolFee = outputValue.mulWadDown(protocolFeeMultiplier);

        // Account for the trade fee, only for Trade pools
        outputValue -= outputValue.mulWadDown(feeMultiplier);

        // Remove the protocol fee from the output amount
        outputValue -= protocolFee;

        // Keep delta the same
        newDelta = delta;

        // If we got all the way here, no math error happened
        error = Error.OK;
    }
}
