// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterSinglePool} from "../base/RouterSinglePool.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RSPXykCurveETHTest is RouterSinglePool, UsingXykCurve, UsingETH {}
