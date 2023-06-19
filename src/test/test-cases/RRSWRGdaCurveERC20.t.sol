// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterRobustSwapWithRoyalties} from "../base/RouterRobustSwapWithRoyalties.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract RRSWRGdaCurveERC20Test is RouterRobustSwapWithRoyalties, UsingGdaCurve, UsingERC20 {}
