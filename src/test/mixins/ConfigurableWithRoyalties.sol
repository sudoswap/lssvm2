// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

import {Test2981} from "../../mocks/Test2981.sol";
import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {TestRoyaltyRegistry} from "../../mocks/TestRoyaltyRegistry.sol";
import {Configurable, IERC721, LSSVMPair, ICurve, IERC721Mintable, LSSVMPairFactory} from "./Configurable.sol";

abstract contract ConfigurableWithRoyalties is Configurable, Test {
    address public constant ROYALTY_RECEIVER = address(420);
    uint96 public constant BPS = 30;
    uint96 public constant BASE = 10_000;

    function setup2981() public returns (ERC2981) {
        return ERC2981(new Test2981(ROYALTY_RECEIVER, BPS));
    }

    function setupRoyaltyEngine() public returns (RoyaltyEngine royaltyEngine) {
        RoyaltyRegistry royaltyRegistry = new RoyaltyRegistry(address(0));
        royaltyRegistry.initialize(address(this));
        royaltyEngine = new RoyaltyEngine(address(royaltyRegistry));
    }

    function addRoyalty(uint256 inputAmount) public pure returns (uint256 outputAmount) {
        return inputAmount + calcRoyalty(inputAmount);
    }

    function subRoyalty(uint256 inputAmount) public pure returns (uint256 outputAmount) {
        return inputAmount - calcRoyalty(inputAmount);
    }

    function calcRoyalty(uint256 inputAmount) public pure returns (uint256 royaltyAmount) {
        royaltyAmount = (inputAmount * BPS) / BASE;
    }

    function calcRoyalty(uint256 inputAmount, uint256 newBps) public pure returns (uint256 royaltyAmount) {
        royaltyAmount = (inputAmount * newBps) / BASE;
    }
}
