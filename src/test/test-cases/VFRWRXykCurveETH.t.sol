// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterWithRoyalties} from "../base/VeryFastRouterWithRoyalties.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract VFRWRXykCurveETHTest is VeryFastRouterWithRoyalties, UsingXykCurve, UsingETH {}
