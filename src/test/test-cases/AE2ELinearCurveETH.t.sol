// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AgreementE2E} from "../base/AgreementE2E.sol";
import {UsingLinearCurve} from "../mixins/UsingLinearCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract AE2ELinearCurveETHTest is AgreementE2E, UsingLinearCurve, UsingETH {}
