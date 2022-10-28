// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterMultiPool} from "../base/RouterMultiPool.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract RMPLinearCurveERC20Test is RouterMultiPool, UsingLinearCurve, UsingERC20 {}
