// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterSinglePool} from "../base/RouterSinglePool.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RSPLinearCurveETHTest is RouterSinglePool, UsingLinearCurve, UsingETH {}
