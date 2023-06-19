// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {NoArbBondingCurve} from "../base/NoArbBondingCurve.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract NoArbGdaCurveERC20Test is NoArbBondingCurve, UsingGdaCurve, UsingERC20 {}
