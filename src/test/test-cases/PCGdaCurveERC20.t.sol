// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {PropertyChecking} from "../base/PropertyChecking.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract PCGdaCurveERC20Test is PropertyChecking, UsingGdaCurve, UsingERC20 {}
