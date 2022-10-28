// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterRobustSwapWithAssetRecipient} from "../base/RouterRobustSwapWithAssetRecipient.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract RRSWARExponentialCurveERC20Test is RouterRobustSwapWithAssetRecipient, UsingExponentialCurve, UsingERC20 {}
