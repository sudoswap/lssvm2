// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterRobustSwap} from "../base/RouterRobustSwap.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RRSLinearCurveETHTest is RouterRobustSwap, UsingLinearCurve, UsingETH {}
