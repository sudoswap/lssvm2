// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SettingsE2E} from "../base/SettingsE2E.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract AE2EExponentialCurveERC20Test is SettingsE2E, UsingExponentialCurve, UsingERC20 {}
