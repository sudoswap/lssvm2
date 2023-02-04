// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SettingsE2E} from "../base/SettingsE2E.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract SE2EXykCurveETHTest is SettingsE2E, UsingXykCurve, UsingETH {}
