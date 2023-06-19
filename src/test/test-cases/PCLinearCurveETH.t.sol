// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {PropertyChecking} from "../base/PropertyChecking.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract PCLinearCurveETHTest is PropertyChecking, UsingLinearCurve, UsingETH {}
