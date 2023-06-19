// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {PairAndFactory} from "../base/PairAndFactory.sol";
import {UsingExponentialCurve} from "../mixins/UsingExponentialCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract PAFExponentialCurveETHTest is PairAndFactory, UsingExponentialCurve, UsingETH {}
