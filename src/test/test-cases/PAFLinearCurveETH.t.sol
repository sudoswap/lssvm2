// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {PairAndFactory} from "../base/PairAndFactory.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract PAFLinearCurveETHTest is PairAndFactory, UsingLinearCurve, UsingETH {}
