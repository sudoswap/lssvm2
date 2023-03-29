// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterWithRoyalties} from "../base/VeryFastRouterWithRoyalties.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract VFRWRExponentialCurveETHTest is VeryFastRouterWithRoyalties, UsingExponentialCurve, UsingETH {}
