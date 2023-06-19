// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterSinglePool} from "../base/RouterSinglePool.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RSPGdaCurveETHTest is RouterSinglePool, UsingGdaCurve, UsingETH {}
