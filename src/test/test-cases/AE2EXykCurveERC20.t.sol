// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AgreementE2E} from "../base/AgreementE2E.sol";
import {UsingXykCurve} from "../mixins/UsingXykCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract AE2EXykCurveERC20Test is AgreementE2E, UsingXykCurve, UsingERC20 {}
