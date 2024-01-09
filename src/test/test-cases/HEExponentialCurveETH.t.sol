// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {HookExecution} from "../base/HookExecution.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract HEExponentialCurveETHTest is HookExecution, UsingExponentialCurve, UsingETH {}
