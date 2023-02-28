// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {MaliciousRouterFailsSwap} from "../base/MaliciousRouterFailsSwap.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract MRFSExponentialCurveERC20Test is MaliciousRouterFailsSwap, UsingExponentialCurve, UsingERC20 {}
