// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {HookExecution} from "../base/HookExecution.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract HEXykCurveETHTest is HookExecution, UsingXykCurve, UsingETH {}
