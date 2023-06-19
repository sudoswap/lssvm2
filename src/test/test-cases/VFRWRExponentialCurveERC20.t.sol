// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VeryFastRouterWithRoyalties} from "../base/VeryFastRouterWithRoyalties.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract VFRWRExponentialCurveERC20Test is VeryFastRouterWithRoyalties, UsingExponentialCurve, UsingERC20 {}
