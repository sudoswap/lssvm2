// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

contract TestRoyaltyRegistry is RoyaltyRegistry {}