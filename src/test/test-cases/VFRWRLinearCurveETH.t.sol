// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterWithRoyalties} from "../base/VeryFastRouterWithRoyalties.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract VFRWRLinearCurveETHTest is VeryFastRouterWithRoyalties, UsingLinearCurve, UsingETH {}
