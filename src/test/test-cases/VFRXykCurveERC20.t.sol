// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterAllSwapTypes} from "../base/VeryFastRouterAllSwapTypes.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract VFRXykCurveERC20Test is VeryFastRouterAllSwapTypes, UsingXykCurve, UsingERC20 {}
