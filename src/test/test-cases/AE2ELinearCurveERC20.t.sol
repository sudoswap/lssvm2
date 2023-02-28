// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SettingsE2E} from "../base/SettingsE2E.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract AE2ELinearCurveERC20Test is SettingsE2E, UsingLinearCurve, UsingERC20 {}
