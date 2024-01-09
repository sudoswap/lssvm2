// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {HookExecution} from "../base/HookExecution.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract HELinearCurveETHTest is HookExecution, UsingLinearCurve, UsingETH {}
