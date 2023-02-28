// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {MaliciousRouterFailsSwap} from "../base/MaliciousRouterFailsSwap.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract MRFSLinearCurveERC20Test is MaliciousRouterFailsSwap, UsingLinearCurve, UsingERC20 {}
