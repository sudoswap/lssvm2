// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

// Gives more realistic scenarios where swaps have to go through multiple pools, for more accurate gas profiling
contract TestRoyaltyRegistry is RoyaltyRegistry {

}
