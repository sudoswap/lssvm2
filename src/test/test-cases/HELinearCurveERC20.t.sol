// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {HookExecution} from "../base/HookExecution.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract HELinearCurveERC20Test is HookExecution, UsingLinearCurve, UsingERC20 {}
