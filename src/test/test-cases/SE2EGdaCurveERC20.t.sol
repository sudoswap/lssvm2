// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SettingsE2E} from "../base/SettingsE2E.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract SE2EGdaCurveERC20Test is SettingsE2E, UsingGdaCurve, UsingERC20 {}
