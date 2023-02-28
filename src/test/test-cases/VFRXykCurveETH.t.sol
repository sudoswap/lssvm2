// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterAllSwapTypes} from "../base/VeryFastRouterAllSwapTypes.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract VFRXykCurveETHTest is VeryFastRouterAllSwapTypes, UsingXykCurve, UsingETH {}
