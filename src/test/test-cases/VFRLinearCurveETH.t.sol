// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterAllSwapTypes} from "../base/VeryFastRouterAllSwapTypes.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract VFRLinearCurveETHTest is VeryFastRouterAllSwapTypes, UsingLinearCurve, UsingETH {}
