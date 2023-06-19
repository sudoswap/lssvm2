// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterAllSwapTypes} from "../base/VeryFastRouterAllSwapTypes.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract VFRLinearCurveERC20Test is VeryFastRouterAllSwapTypes, UsingLinearCurve, UsingERC20 {}
