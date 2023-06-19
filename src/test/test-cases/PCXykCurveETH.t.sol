// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {PropertyChecking} from "../base/PropertyChecking.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract PCXykCurveETHTest is PropertyChecking, UsingXykCurve, UsingETH {}
