// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SettingsE2E} from "../base/SettingsE2E.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract AE2EExponentialCurveETHTest is SettingsE2E, UsingExponentialCurve, UsingETH {}
