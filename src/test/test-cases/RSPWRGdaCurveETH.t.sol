// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {RouterSinglePoolWithRoyalties} from "../base/RouterSinglePoolWithRoyalties.sol";
import {UsingGdaCurve} from "../mixins/UsingGdaCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract RSPWRGdaCurveETHTest is RouterSinglePoolWithRoyalties, UsingGdaCurve, UsingETH {}
