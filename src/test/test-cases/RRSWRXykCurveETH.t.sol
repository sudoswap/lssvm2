// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterRobustSwapWithRoyalties} from "../base/RouterRobustSwapWithRoyalties.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RRSWRXykCurveETHTest is RouterRobustSwapWithRoyalties, UsingXykCurve, UsingETH {}
