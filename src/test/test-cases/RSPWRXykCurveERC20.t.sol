// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterSinglePoolWithRoyalties} from "../base/RouterSinglePoolWithRoyalties.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract RSPWRXykCurveERC20Test is RouterSinglePoolWithRoyalties, UsingXykCurve, UsingERC20 {}
