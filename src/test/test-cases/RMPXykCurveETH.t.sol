// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterMultiPool} from "../base/RouterMultiPool.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RMPXykCurveETHTest is RouterMultiPool, UsingXykCurve, UsingETH {}
