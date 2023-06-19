// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterMultiPool} from "../base/RouterMultiPool.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract RMPExponentialCurveERC20Test is RouterMultiPool, UsingExponentialCurve, UsingERC20 {}
