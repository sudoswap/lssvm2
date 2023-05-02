// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UD60x18, convert, ud, unwrap, PRBMath_UD60x18_Exp2_InputTooBig} from "@prb/math/UD60x18.sol";

import {GDACurve} from "../../bonding-curves/GDACurve.sol";
import {CurveErrorCodes} from "../../bonding-curves/CurveErrorCodes.sol";

contract GDACurveTest is Test {
    using Strings for uint256;

    struct ScriptArgs {
        uint256 initialPrice;
        uint256 scaleFactor;
        uint256 decayConstant;
        uint256 numTotalPurchases;
        uint256 timeSinceStart;
        uint256 quantity;
    }

    uint256 internal constant _SCALE_FACTOR = 1e9;

    uint256 internal alpha = unwrap(convert(15).div(convert(10)));
    uint256 internal lambda = unwrap(convert(1).div(convert(100)));

    GDACurve curve;

    function setUp() public {
        curve = new GDACurve();
    }

    function getPackedDelta(uint48 time) public view returns (uint128) {
        uint40 _alpha = uint40(alpha / _SCALE_FACTOR);
        uint40 _lambda = uint40(lambda / _SCALE_FACTOR);
        return ((uint128(_alpha) << 88)) | ((uint128(_lambda) << 48)) | uint128(time);
    }

    function test_getBuyInfoExample() public {
        uint48 t0 = 5;
        uint48 t1 = 10;
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 expectedNewDelta = getPackedDelta(uint48(t1));
        uint128 numItemsAlreadyPurchased = 1;
        uint128 initialPrice = 10 ether;
        uint128 adjustedSpotPrice;
        {
            UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadyPurchased);
            adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));
        }

        // Check outputs against Python script
        {
            uint128 numItemsToBuy = 5;
            (
                CurveErrorCodes.Error error,
                uint128 newSpotPrice,
                uint128 newDelta,
                uint256 inputValue,
                ,
                uint256 protocolFee
            ) = curve.getBuyInfo(adjustedSpotPrice, delta, numItemsToBuy, 0, 0);

            uint48 tDelta = t1 - t0;
            ScriptArgs memory args =
                ScriptArgs(initialPrice, alpha, lambda, numItemsAlreadyPurchased, tDelta, numItemsToBuy);
            uint256 expectedInputValue = calculateValue("buy_input_value", args);
            uint256 expectedNewSpotPrice = calculateValue("buy_spot_price", args);

            assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
            assertApproxEqRel(newSpotPrice, expectedNewSpotPrice, 1e9, "Spot price incorrect");
            assertEq(newDelta, expectedNewDelta, "Delta incorrect");
            assertApproxEqRel(inputValue, expectedInputValue, 1e9, "Input value incorrect");
            assertEq(protocolFee, 0, "Protocol fee incorrect");

            // Update values
            adjustedSpotPrice = newSpotPrice;
            numItemsAlreadyPurchased += numItemsToBuy;
            delta = newDelta;
        }

        // Validate that the new values are correct
        {
            // Move time forward
            uint48 t2 = 13;
            vm.warp(t2);
            expectedNewDelta = getPackedDelta(uint48(t2));

            uint128 numItemsToBuy = 2;
            (CurveErrorCodes.Error error, uint128 newSpotPrice, uint128 newDelta, uint256 inputValue,,) =
                curve.getBuyInfo(adjustedSpotPrice, delta, numItemsToBuy, 0, 0);

            uint48 tDelta = t2 - t0;
            ScriptArgs memory args =
                ScriptArgs(initialPrice, alpha, lambda, numItemsAlreadyPurchased, tDelta, numItemsToBuy);
            uint256 expectedInputValue = calculateValue("buy_input_value", args);
            uint256 expectedNewSpotPrice = calculateValue("buy_spot_price", args);

            assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
            assertApproxEqRel(newSpotPrice, expectedNewSpotPrice, 1e9, "Spot price incorrect");
            assertEq(newDelta, expectedNewDelta, "Delta incorrect");
            assertApproxEqRel(inputValue, expectedInputValue, 1e9, "Input value incorrect");

            // Update values
            adjustedSpotPrice = newSpotPrice;
            numItemsAlreadyPurchased += numItemsToBuy;
            delta = newDelta;
        }

        {
            // Move time forward
            uint48 t3 = 100;
            vm.warp(t3);
            expectedNewDelta = getPackedDelta(uint48(t3));

            uint128 numItemsToBuy = 4;
            (CurveErrorCodes.Error error, uint128 newSpotPrice, uint128 newDelta, uint256 inputValue,,) =
                curve.getBuyInfo(adjustedSpotPrice, delta, numItemsToBuy, 0, 0);

            uint48 tDelta = t3 - t0;
            ScriptArgs memory args =
                ScriptArgs(initialPrice, alpha, lambda, numItemsAlreadyPurchased, tDelta, numItemsToBuy);
            uint256 expectedInputValue = calculateValue("buy_input_value", args);
            uint256 expectedNewSpotPrice = calculateValue("buy_spot_price", args);

            assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
            assertApproxEqRel(newSpotPrice, expectedNewSpotPrice, 1e9, "Spot price incorrect");
            assertEq(newDelta, expectedNewDelta, "Delta incorrect");
            assertApproxEqRel(inputValue, expectedInputValue, 1e9, "Input value incorrect");
        }
    }

    function testGasBuyInfo() public {
        uint48 t0 = 5;
        uint48 t1 = 10;
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 numItemsAlreadyPurchased = 1;
        uint128 initialPrice = 10 ether;
        uint128 adjustedSpotPrice;
        {
            UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadyPurchased);
            adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));
        }

        uint128 numItemsToBuy = 5;
        uint256 gasLeft = gasleft();
        curve.getBuyInfo(adjustedSpotPrice, delta, numItemsToBuy, 0, 0);
        assertTrue(gasLeft - gasleft() < 14000);
    }

    function test_getBuyInfoWithFees() public {
        uint48 t0 = 5;
        uint48 t1 = 10;
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 initialPrice = 10 ether;
        uint128 adjustedSpotPrice;
        {
            UD60x18 alphaPowM = ud(alpha).powu(1);
            adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));
        }

        // Check outputs against Python script
        {
            uint256 feeMultiplier = unwrap(convert(4).div(convert(100)));
            uint256 protocolFeeMultiplier = unwrap(convert(1).div(convert(100)));
            uint128 numItemsToBuy = 5;
            (CurveErrorCodes.Error error,,, uint256 inputValue, uint256 tradeFee, uint256 protocolFee) =
                curve.getBuyInfo(adjustedSpotPrice, delta, numItemsToBuy, feeMultiplier, protocolFeeMultiplier);

            uint48 tDelta = t1 - t0;
            ScriptArgs memory args = ScriptArgs(initialPrice, alpha, lambda, 1, tDelta, numItemsToBuy);
            uint256 rawInputValue = calculateValue("buy_input_value", args);
            uint256 expectedInputValue = unwrap(ud(rawInputValue).mul(convert(105)).div(convert(100)));

            assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
            assertApproxEqRel(inputValue, expectedInputValue, 1e9, "Input value incorrect");
            assertApproxEqRel(
                protocolFee, unwrap(ud(rawInputValue).mul(ud(protocolFeeMultiplier))), 1e9, "Protocol fee incorrect"
            );
            assertApproxEqRel(tradeFee, unwrap(ud(rawInputValue).mul(ud(feeMultiplier))), 1e9, "Trade fee incorrect");
        }
    }

    function test_getBuyInfoTimeDecayTooLarge() public {
        uint48 t0 = 0;
        uint48 t1 = uint48(100000);
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 numItemsAlreadyPurchased = 0;
        uint128 initialPrice = 10 ether;
        UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadyPurchased);
        uint128 adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));

        ScriptArgs memory args = ScriptArgs(initialPrice, alpha, lambda, numItemsAlreadyPurchased, 1000, 5);
        uint256 expectedInputValue = calculateValue("buy_input_value", args);

        (CurveErrorCodes.Error error,,, uint256 inputValue,,) = curve.getBuyInfo(adjustedSpotPrice, delta, 5, 0, 0);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK));
        assertApproxEqRel(inputValue, expectedInputValue, 1e9, "Input value incorrect");
    }

    function test_getBuyInfoOverflow() public {
        uint48 t0 = 0;
        uint48 t1 = uint48(1);
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 numItemsAlreadyPurchased = 329;
        uint128 initialPrice = 10 ether;
        UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadyPurchased);
        uint128 adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));

        (CurveErrorCodes.Error error,,,,,) = curve.getBuyInfo(adjustedSpotPrice, delta, 5, 0, 0);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.SPOT_PRICE_OVERFLOW));
    }

    function test_getBuyInfoUnderflow() public {
        uint48 t0 = 0;
        uint48 t1 = uint48(1);
        vm.warp(t1);

        lambda = unwrap(convert(100000));
        uint128 delta = getPackedDelta(t0);
        uint128 adjustedSpotPrice = uint128(10 gwei);

        (CurveErrorCodes.Error error,,,,,) = curve.getBuyInfo(adjustedSpotPrice, delta, 5, 0, 0);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.SPOT_PRICE_UNDERFLOW));
    }

    function test_getBuyInfoFuzz(uint48 t1) public {
        lambda = unwrap(convert(1).div(convert(10000000)));

        uint48 t0 = 0;
        t1 = uint48(bound(t1, 1, 25920000)); // 300 days
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 numItemsAlreadyPurchased = 0;
        uint128 initialPrice = 10 ether;
        UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadyPurchased);
        uint128 adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));

        // Make sure there are no PRBMath issues
        (CurveErrorCodes.Error error,,,,,) = curve.getBuyInfo(adjustedSpotPrice, delta, 5, 0, 0);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
    }

    function test_getSellInfoExample() public {
        uint48 t0 = 5;
        uint48 t1 = 10;
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 expectedNewDelta = getPackedDelta(uint48(t1));
        uint128 numItemsAlreadySold = 2;
        uint128 initialPrice = 1 ether;
        uint128 adjustedSpotPrice;
        {
            UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadySold);
            adjustedSpotPrice = uint128(unwrap(ud(initialPrice).div(alphaPowM)));
        }

        // Check outputs against Python script
        {
            uint128 numItemsToSell = 1;
            (
                CurveErrorCodes.Error error,
                uint128 newSpotPrice,
                uint128 newDelta,
                uint256 outputValue,
                ,
                uint256 protocolFee
            ) = curve.getSellInfo(adjustedSpotPrice, delta, numItemsToSell, 0, 0);

            uint48 tDelta = t1 - t0;
            ScriptArgs memory args =
                ScriptArgs(initialPrice, alpha, lambda, numItemsAlreadySold, tDelta, numItemsToSell);
            uint256 expectedOutputValue = calculateValue("sell_output_value", args);
            uint256 expectedNewSpotPrice = calculateValue("sell_spot_price", args);

            assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
            assertApproxEqRel(newSpotPrice, expectedNewSpotPrice, 1e9, "Spot price incorrect");
            assertEq(newDelta, expectedNewDelta, "Delta incorrect");
            assertApproxEqRel(outputValue, expectedOutputValue, 1e9, "Output value incorrect");
            assertEq(protocolFee, 0, "Protocol fee incorrect");

            // Update values
            adjustedSpotPrice = newSpotPrice;
            numItemsAlreadySold += numItemsToSell;
            delta = newDelta;
        }

        // Validate that the new values are correct
        {
            // Move time forward
            uint48 t2 = 13;
            vm.warp(t2);
            expectedNewDelta = getPackedDelta(uint48(t2));

            uint128 numItemsToSell = 4;
            (CurveErrorCodes.Error error, uint128 newSpotPrice, uint128 newDelta, uint256 outputValue,,) =
                curve.getSellInfo(adjustedSpotPrice, delta, numItemsToSell, 0, 0);

            uint48 tDelta = t2 - t0;
            ScriptArgs memory args =
                ScriptArgs(initialPrice, alpha, lambda, numItemsAlreadySold, tDelta, numItemsToSell);
            uint256 expectedOutputValue = calculateValue("sell_output_value", args);
            uint256 expectedNewSpotPrice = calculateValue("sell_spot_price", args);

            assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
            assertApproxEqRel(newSpotPrice, expectedNewSpotPrice, 1e9, "Spot price incorrect");
            assertEq(newDelta, expectedNewDelta, "Delta incorrect");
            assertApproxEqRel(outputValue, expectedOutputValue, 1e9, "Output value incorrect");

            // Update values
            adjustedSpotPrice = newSpotPrice;
            numItemsAlreadySold += numItemsToSell;
            delta = newDelta;
        }

        {
            // Move time forward
            uint48 t3 = 200;
            vm.warp(t3);
            expectedNewDelta = getPackedDelta(uint48(t3));

            uint128 numItemsToSell = 6;
            (CurveErrorCodes.Error error, uint128 newSpotPrice, uint128 newDelta, uint256 outputValue,,) =
                curve.getSellInfo(adjustedSpotPrice, delta, numItemsToSell, 0, 0);

            uint48 tDelta = t3 - t0;
            ScriptArgs memory args =
                ScriptArgs(initialPrice, alpha, lambda, numItemsAlreadySold, tDelta, numItemsToSell);
            uint256 expectedOutputValue = calculateValue("sell_output_value", args);
            uint256 expectedNewSpotPrice = calculateValue("sell_spot_price", args);

            assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
            assertApproxEqRel(newSpotPrice, expectedNewSpotPrice, 1e9, "Spot price incorrect");
            assertEq(newDelta, expectedNewDelta, "Delta incorrect");
            assertApproxEqRel(outputValue, expectedOutputValue, 1e9, "Output value incorrect");

            // Update values
            adjustedSpotPrice = newSpotPrice;
            numItemsAlreadySold += numItemsToSell;
            delta = newDelta;
        }
    }

    function test_getSellInfoWithFees() public {
        uint48 t0 = 5;
        uint48 t1 = 10;
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 initialPrice = 1 ether;
        uint128 adjustedSpotPrice;
        {
            UD60x18 alphaPowM = ud(alpha).powu(2);
            adjustedSpotPrice = uint128(unwrap(ud(initialPrice).div(alphaPowM)));
        }

        // Check outputs against Python script
        {
            uint256 feeMultiplier = unwrap(convert(4).div(convert(100)));
            uint256 protocolFeeMultiplier = unwrap(convert(1).div(convert(100)));
            uint128 numItemsToSell = 1;
            (CurveErrorCodes.Error error,,, uint256 outputValue, uint256 tradeFee, uint256 protocolFee) =
                curve.getSellInfo(adjustedSpotPrice, delta, numItemsToSell, feeMultiplier, protocolFeeMultiplier);

            uint48 tDelta = t1 - t0;
            ScriptArgs memory args = ScriptArgs(initialPrice, alpha, lambda, 2, tDelta, numItemsToSell);
            uint256 rawOutputValue = calculateValue("sell_output_value", args);
            uint256 expectedOutputValue = unwrap(ud(rawOutputValue).mul(convert(95)).div(convert(100)));

            assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
            assertApproxEqRel(outputValue, expectedOutputValue, 1e9, "Output value incorrect");
            assertApproxEqRel(
                protocolFee, unwrap(ud(rawOutputValue).mul(ud(protocolFeeMultiplier))), 1e9, "Protocol fee incorrect"
            );
            assertApproxEqRel(tradeFee, unwrap(ud(rawOutputValue).mul(ud(feeMultiplier))), 1e9, "Trade fee incorrect");
        }
    }

    function testGasSellInfo() public {
        uint48 t0 = 5;
        uint48 t1 = 10;
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 numItemsAlreadySold = 2;
        uint128 initialPrice = 1 ether;
        uint128 adjustedSpotPrice;
        {
            UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadySold);
            adjustedSpotPrice = uint128(unwrap(ud(initialPrice).div(alphaPowM)));
        }

        uint128 numItemsToSell = 1;
        uint256 gasLeft = gasleft();
        curve.getSellInfo(adjustedSpotPrice, delta, numItemsToSell, 0, 0);
        assertTrue(gasLeft - gasleft() < 14000);
    }

    function test_getSellInfoTimeBoostTooLarge() public {
        uint48 t0 = 0;
        uint48 t1 = uint48(100000);
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 numItemsAlreadySold = 0;
        uint128 initialPrice = 10 ether;
        UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadySold);
        uint128 adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));

        ScriptArgs memory args = ScriptArgs(initialPrice, alpha, lambda, numItemsAlreadySold, 1000, 5);
        uint256 expectedOutputValue = calculateValue("sell_output_value", args);

        (CurveErrorCodes.Error error,,, uint256 outputValue,,) = curve.getSellInfo(adjustedSpotPrice, delta, 5, 0, 0);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK));
        assertApproxEqRel(outputValue, expectedOutputValue, 1e9, "Output value incorrect");
    }

    function test_getSellInfoOverflow() public {
        uint48 t0 = 0;
        uint48 t1 = uint48(10000);
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 numItemsAlreadySold = 0;
        uint128 initialPrice = 10000000000000000000 ether;
        UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadySold);
        uint128 adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));

        (CurveErrorCodes.Error error,,,,,) = curve.getSellInfo(adjustedSpotPrice, delta, 5, 0, 0);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.SPOT_PRICE_OVERFLOW));
    }

    function test_getSellInfoUnderflow() public {
        uint48 t0 = 0;
        uint48 t1 = uint48(1);
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 adjustedSpotPrice = uint128(5 gwei);

        (CurveErrorCodes.Error error,,,,,) = curve.getSellInfo(adjustedSpotPrice, delta, 5, 0, 0);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.SPOT_PRICE_UNDERFLOW));
    }

    function test_getSellInfoFuzz(uint48 t1) public {
        lambda = unwrap(convert(1).div(convert(10000000)));

        uint48 t0 = 0;
        t1 = uint48(bound(t1, 1, 25920000)); // 300 days
        vm.warp(t1);

        uint128 delta = getPackedDelta(t0);
        uint128 numItemsAlreadySold = 0;
        uint128 initialPrice = 10 ether;
        UD60x18 alphaPowM = ud(alpha).powu(numItemsAlreadySold);
        uint128 adjustedSpotPrice = uint128(unwrap(ud(initialPrice).mul(alphaPowM)));

        // Make sure there are no PRBMath issues
        (CurveErrorCodes.Error error,,,,,) = curve.getSellInfo(adjustedSpotPrice, delta, 5, 0, 0);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Error code not OK");
    }

    // Call python script for price computation
    function calculateValue(string memory functionName, ScriptArgs memory args) private returns (uint256) {
        string[] memory inputs = new string[](15);
        inputs[0] = "python3";
        inputs[1] = "src/test/gda-analysis/compute_price.py";
        inputs[2] = functionName;
        inputs[3] = "--initial_price";
        inputs[4] = uint256(args.initialPrice).toString();
        inputs[5] = "--scale_factor";
        inputs[6] = uint256(args.scaleFactor).toString();
        inputs[7] = "--decay_constant";
        inputs[8] = uint256(args.decayConstant).toString();
        inputs[9] = "--num_total_purchases";
        inputs[10] = args.numTotalPurchases.toString();
        inputs[11] = "--time_since_start";
        inputs[12] = args.timeSinceStart.toString();
        inputs[13] = "--quantity";
        inputs[14] = args.quantity.toString();
        bytes memory res = vm.ffi(inputs);
        uint256 price = abi.decode(res, (uint256));
        return price;
    }
}
