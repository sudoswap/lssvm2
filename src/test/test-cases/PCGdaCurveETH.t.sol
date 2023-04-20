// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {PropertyChecking} from "../base/PropertyChecking.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract PCGdaCurveETHTest is PropertyChecking, UsingGdaCurve, UsingETH {}
