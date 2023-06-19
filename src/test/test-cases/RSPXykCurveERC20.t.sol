// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterSinglePool} from "../base/RouterSinglePool.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract RSPXykCurveERC20Test is RouterSinglePool, UsingXykCurve, UsingERC20 {}
