// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AgreementE2E} from "../base/AgreementE2E.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingERC20} from "../mixins/UsingERC20.sol";

contract AE2ELinearCurveERC20Test is AgreementE2E, UsingLinearCurve, UsingERC20 {}
