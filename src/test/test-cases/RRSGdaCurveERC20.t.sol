// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterRobustSwap} from "../base/RouterRobustSwap.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract RRSGdaCurveERC20Test is RouterRobustSwap, UsingGdaCurve, UsingERC20 {}
