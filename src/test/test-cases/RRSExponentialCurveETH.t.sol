// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterRobustSwap} from "../base/RouterRobustSwap.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RRSExponentialCurveETHTest is RouterRobustSwap, UsingExponentialCurve, UsingETH {}
