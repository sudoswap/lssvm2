// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {Test2981} from "../../mocks/Test2981.sol";
import {Test721} from "../../mocks/Test721.sol";
import {TestManifold} from "../../mocks/TestManifold.sol";

contract RoyaltyEngineTest is Test {
    int16 private constant NONE = -1;
    int16 private constant NOT_CONFIGURED = 0;
    int16 private constant MANIFOLD = 1;
    int16 private constant RARIBLEV1 = 2;
    int16 private constant RARIBLEV2 = 3;
    int16 private constant FOUNDATION = 4;
    int16 private constant EIP2981 = 5;
    int16 private constant SUPERRARE = 6;
    int16 private constant ZORA = 7;
    int16 private constant ARTBLOCKS = 8;
    int16 private constant KNOWNORIGINV2 = 9;

    RoyaltyRegistry registry;
    RoyaltyEngine engine;

    Test2981 nft1;
    Test721 nft2;
    Test2981 royaltyLookup1;
    TestManifold royaltyLookup2;

    function setUp() public {
        nft1 = new Test2981(vm.addr(420), 300);
        nft2 = new Test721();
        royaltyLookup1 = new Test2981(vm.addr(100), 450);
        address payable[] memory receivers = new address payable[](1);
        receivers[0] = payable(vm.addr(1));
        uint256[] memory bps = new uint256[](1);
        bps[0] = 750;
        royaltyLookup2 = new TestManifold(receivers, bps);

        registry = new RoyaltyRegistry(address(0));
        registry.initialize(address(this));
        registry.setRoyaltyLookupAddress(address(nft2), address(royaltyLookup1));
        engine = new RoyaltyEngine(address(registry));
    }

    function testBulkCacheSpecsSuccess() public {
        assertEq(engine.getCachedRoyaltySpec(address(nft1)), NOT_CONFIGURED);
        assertEq(engine.getCachedRoyaltySpec(address(nft2)), NOT_CONFIGURED);

        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(nft1);
        tokenAddresses[1] = address(nft2);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 1;
        uint256[] memory values = new uint256[](2);
        values[0] = 1 ether;
        values[1] = 1 ether;

        engine.bulkCacheSpecs(tokenAddresses, tokenIds, values);
        assertEq(engine.getCachedRoyaltySpec(address(nft1)), EIP2981);
        assertEq(engine.getCachedRoyaltySpec(address(nft2)), EIP2981);
        (address payable[] memory recipients, uint256[] memory amounts) = engine.getRoyalty(address(nft2), 1, 1 ether);
        assertEq(recipients[0], vm.addr(100));
        assertEq(amounts[0], 0.045 ether);

        // Test that a second call leads to the same results
        engine.bulkCacheSpecs(tokenAddresses, tokenIds, values);
        assertEq(engine.getCachedRoyaltySpec(address(nft1)), EIP2981);
        assertEq(engine.getCachedRoyaltySpec(address(nft2)), EIP2981);

        // Change the lookup for nft2
        registry.setRoyaltyLookupAddress(address(nft2), address(royaltyLookup2));

        // Make sure the spec on nft2 changed
        engine.bulkCacheSpecs(tokenAddresses, tokenIds, values);
        assertEq(engine.getCachedRoyaltySpec(address(nft1)), EIP2981);
        assertEq(engine.getCachedRoyaltySpec(address(nft2)), MANIFOLD);
        (recipients, amounts) = engine.getRoyalty(address(nft2), 1, 1 ether);
        assertEq(recipients[0], vm.addr(1));
        assertEq(amounts[0], 0.075 ether);
    }

    function testBulkCacheSpecsFailure() public {
        assertEq(engine.getCachedRoyaltySpec(address(nft1)), NOT_CONFIGURED);
        assertEq(engine.getCachedRoyaltySpec(address(nft2)), NOT_CONFIGURED);

        // Make the manifold lookup value too high
        address payable[] memory receivers = new address payable[](1);
        receivers[0] = payable(vm.addr(1));
        uint256[] memory bps = new uint256[](1);
        bps[0] = 10001;
        royaltyLookup2 = new TestManifold(receivers, bps);

        // Change the lookup for nft2
        registry.setRoyaltyLookupAddress(address(nft2), address(royaltyLookup2));

        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(nft1);
        tokenAddresses[1] = address(nft2);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 1;
        uint256[] memory values = new uint256[](2);
        values[0] = 1 ether;
        values[1] = 1 ether;

        vm.expectRevert(RoyaltyEngine.RoyaltyEngine__InvalidRoyaltyAmount.selector);
        engine.bulkCacheSpecs(tokenAddresses, tokenIds, values);
        assertEq(engine.getCachedRoyaltySpec(address(nft1)), NOT_CONFIGURED);
        assertEq(engine.getCachedRoyaltySpec(address(nft2)), NOT_CONFIGURED);
    }

    function testGetRoyalty() public {
        (address payable[] memory recipients, uint256[] memory amounts) = engine.getRoyalty(address(nft1), 1, 1 ether);
        assertEq(recipients[0], vm.addr(420));
        assertEq(amounts[0], 0.03 ether);

        (recipients, amounts) = engine.getRoyaltyView(address(nft1), 1, 1 ether);
        assertEq(recipients[0], vm.addr(420));
        assertEq(amounts[0], 0.03 ether);

        // Change nft2 to use manifold
        address nft2Receiver = vm.addr(1);
        address payable[] memory receivers = new address payable[](1);
        receivers[0] = payable(nft2Receiver);
        uint256[] memory bps = new uint256[](1);
        bps[0] = 550;
        royaltyLookup2 = new TestManifold(receivers, bps);
        registry.setRoyaltyLookupAddress(address(nft2), address(royaltyLookup2));

        (recipients, amounts) = engine.getRoyalty(address(nft2), 1, 1 ether);
        assertEq(recipients[0], nft2Receiver);
        assertEq(amounts[0], 0.055 ether);

        (recipients, amounts) = engine.getRoyaltyView(address(nft2), 1, 1 ether);
        assertEq(recipients[0], nft2Receiver);
        assertEq(amounts[0], 0.055 ether);
    }
}
