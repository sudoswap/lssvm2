// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterWithRoyalties} from "../base/VeryFastRouterWithRoyalties.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract VFRWRLinearCurveERC20Test is VeryFastRouterWithRoyalties, UsingLinearCurve, UsingERC20 {}
