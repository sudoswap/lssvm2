// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterRobustSwapWithAssetRecipient} from "../base/RouterRobustSwapWithAssetRecipient.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RRSWARGdaCurveETHTest is RouterRobustSwapWithAssetRecipient, UsingGdaCurve, UsingETH {}
