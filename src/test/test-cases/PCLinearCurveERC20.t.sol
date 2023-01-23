// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {PropertyChecking} from "../base/PropertyChecking.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract PCLinearCurveERC20Test is PropertyChecking, UsingLinearCurve, UsingERC20 {}
