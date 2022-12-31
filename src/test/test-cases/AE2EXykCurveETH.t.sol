// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AgreementE2E} from "../base/AgreementE2E.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract AE2EXykCurveETHTest is AgreementE2E, UsingXykCurve, UsingETH {}
