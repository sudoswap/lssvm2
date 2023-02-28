// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {MaliciousRouterFailsSwap} from "../base/MaliciousRouterFailsSwap.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract MRFSExponentialCurveETHTest is MaliciousRouterFailsSwap, UsingExponentialCurve, UsingETH {}
