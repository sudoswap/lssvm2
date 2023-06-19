// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {MaliciousRouterFailsSwap} from "../base/MaliciousRouterFailsSwap.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract MRFSXykCurveERC20Test is MaliciousRouterFailsSwap, UsingXykCurve, UsingERC20 {}
