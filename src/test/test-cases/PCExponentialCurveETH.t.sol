// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {PropertyChecking} from "../base/PropertyChecking.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract PCExponentialCurveETHTest is PropertyChecking, UsingExponentialCurve, UsingETH {}
