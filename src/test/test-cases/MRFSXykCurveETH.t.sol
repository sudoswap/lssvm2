// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {MaliciousRouterFailsSwap} from "../base/MaliciousRouterFailsSwap.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract MRFSXykCurveETHTest is MaliciousRouterFailsSwap, UsingXykCurve, UsingETH {}
