// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {IOwnable} from "../interfaces/IOwnable.sol";
import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {ILSSVMPairFactoryLike} from "../../ILSSVMPairFactoryLike.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";

import {StandardAgreement} from "../../agreements/StandardAgreement.sol";
import {StandardAgreementFactory} from "../../agreements/StandardAgreementFactory.sol";
import {Splitter} from "../../agreements/Splitter.sol";

import {Test20} from "../../mocks/Test20.sol";
import {Test721} from "../../mocks/Test721.sol";
import {Test1155} from "../../mocks/Test1155.sol";
import {TestManifold} from "../../mocks/TestManifold.sol";
import {MockPair} from "../../mocks/MockPair.sol";

abstract contract AgreementE2E is Test, ERC721Holder, ConfigurableWithRoyalties {
    uint128 delta = 1.1 ether;
    uint128 spotPrice = 20 ether;
    uint256 tokenAmount = 100 ether;
    uint256 numItems = 3;
    uint256 agreementFee = 0.1 ether;
    uint64 agreementLockup = 1 days;
    uint256[] idList;
    ERC2981 test2981;
    IERC721 test721;
    IERC721 test721Other;
    ERC20 testERC20;
    ICurve bondingCurve;
    LSSVMPairFactory factory;
    address payable constant feeRecipient = payable(address(69));
    LSSVMPair pair;
    MockPair mockPair;
    RoyaltyEngine royaltyEngine;
    StandardAgreementFactory agreementFactory;
    StandardAgreement agreement;

    function setUp() public {
        bondingCurve = setupCurve();
        test721 = setup721();
        test2981 = setup2981();
        test721Other = new Test721();
        royaltyEngine = setupRoyaltyEngine();

        // Set a royalty override
        IRoyaltyRegistry(royaltyEngine.royaltyRegistry()).setRoyaltyLookupAddress(address(test721), address(test2981));

        // Set up the pair factory
        factory = setupFactory(royaltyEngine, feeRecipient);
        factory.setBondingCurveAllowed(bondingCurve, true);
        test721.setApprovalForAll(address(factory), true);
        // Mint IDs from 1 to numItems to the caller, to deposit into the pair
        for (uint256 i = 1; i <= numItems; i++) {
            IERC721Mintable(address(test721)).mint(address(this), i);
            idList.push(i);
        }
        pair = this.setupPair{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)), // asset recipient
            LSSVMPair.PoolType.TRADE,
            delta,
            0, // 0% for trade fee
            spotPrice,
            idList,
            tokenAmount,
            address(0)
        );
        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair), 1 ether);
        test721.setApprovalForAll(address(pair), true);
        testERC20.approve(address(pair), 10000 ether);

        // Agreement setup
        Splitter splitterImplementation = new Splitter();
        StandardAgreement agreementImplementation = new StandardAgreement(
            splitterImplementation,
            factory
        );
        agreementFactory = new StandardAgreementFactory(
            agreementImplementation
        );

        agreement = agreementFactory.createAgreement(feeRecipient, agreementFee, agreementLockup, 5, 500);
        mockPair = new MockPair();
    }

    // Pair Factory permissions with adding/removing Agreements and toggling override royalty bps for pools

    // An authorized caller can correctly add/remove an Agreement on the factory
    function test_addAgreementAsAuth() public {
        address agreementAddress = address(69420);
        factory.toggleAgreementForCollection(agreementAddress, address(test721), true);
        assertEq(factory.agreementsForCollection(address(test721), agreementAddress), true);
        factory.toggleAgreementForCollection(agreementAddress, address(test721), false);
        assertEq(factory.agreementsForCollection(address(test721), agreementAddress), false);
    }

    // An unauthorized caller cannot add/remove an Agreement on the factory
    function test_addAgreementAsNotAuth() public {
        IOwnable(address(test721)).transferOwnership(address(12345));
        vm.expectRevert("Unauthorized caller");
        factory.toggleAgreementForCollection(address(1), address(test721), true);

        vm.expectRevert("Unauthorized caller");
        factory.toggleAgreementForCollection(address(1), address(test721), false);
    }

    function test_enableAgreementForPair() public {
        factory.toggleAgreementForCollection(address(agreement), address(test721), true);

        // This call will trigger the callback to call enableAgreementForPair on the factory
        pair.transferOwnership{value: 0.1 ether}(address(agreement), "");
        assertEq(factory.agreementForPair(address(pair)), address(agreement));
        (bool isInAgreement, uint96 royaltyBps) = factory.getAgreementForPair(address(pair));
        assertEq(isInAgreement, true);
        assertEq(royaltyBps, 500);
    }

    function test_enableAgreementForPairIdempotent() public {
        factory.toggleAgreementForCollection(address(agreement), address(test721), true);

        // First call will be done directly on the factory
        factory.enableAgreementForPair(address(agreement), address(pair));
        assertEq(factory.agreementForPair(address(pair)), address(agreement));

        // Second call will also make a call to the factory due to the callback
        pair.transferOwnership{value: 0.1 ether}(address(agreement), "");
        assertEq(factory.agreementForPair(address(pair)), address(agreement));
    }

    function test_enableAgreementForPairNotPairOwner() public {
        factory.toggleAgreementForCollection(address(this), address(test721Other), true);
        vm.expectRevert("Msg sender is not pair owner");
        vm.prank(vm.addr(1));
        factory.enableAgreementForPair(address(this), address(pair));
    }

    function test_enableAgreementForPairAgreementNotEnabled() public {
        vm.expectRevert("Agreement not enabled for collection");
        pair.transferOwnership{value: 0.1 ether}(address(agreement), "");
    }

    function test_enableAgreementForPairAgreementNotPair() public {
        vm.expectRevert("Invalid pair address");
        factory.enableAgreementForPair(address(this), address(this));
    }

    function test_disableAgreementForPair() public {
        factory.toggleAgreementForCollection(address(agreement), address(test721), true);
        pair.transferOwnership{value: 0.1 ether}(address(agreement), "");

        // Cannot reclaim pair until lockup period has passed
        vm.expectRevert("Lockup not over");
        agreement.reclaimPair(address(pair));

        // Move forward in time so lockup period is over
        vm.warp(block.timestamp + 1 days + 1 seconds);

        agreement.reclaimPair(address(pair));
        assertEq(factory.agreementForPair(address(pair)), address(0));
        (bool isInAgreement, uint96 royaltyBps) = factory.getAgreementForPair(address(pair));
        assertEq(isInAgreement, false);
        assertEq(royaltyBps, 0);
    }

    function test_disableAgreementForPairNotPair() public {
        vm.expectRevert("Invalid pair address");
        factory.disableAgreementForPair(address(this), address(this));
    }

    function test_disableAgreementForPairNotEnabled() public {
        vm.expectRevert("Agreement not enabled for pair");
        factory.disableAgreementForPair(address(agreement), address(pair));
    }

    function test_disableAgreementNotPairOwner() public {
        factory.toggleAgreementForCollection(address(agreement), address(test721), true);
        pair.transferOwnership{value: 0.1 ether}(address(agreement), "");

        vm.expectRevert("Msg sender is not pair owner");
        factory.disableAgreementForPair(address(agreement), address(pair));
    }

    function test_getAllPairsForAgreement() public {
        address[] memory results = factory.getAllPairsForAgreement(address(agreement));
        assertEq(results.length, 0);

        // Add pair to agreement
        factory.toggleAgreementForCollection(address(agreement), address(test721), true);
        pair.transferOwnership{value: 0.1 ether}(address(agreement), "");

        results = factory.getAllPairsForAgreement(address(agreement));
        assertEq(results.length, 1);
        assertEq(results[0], address(pair));

        // Add another pair to agreement
        uint256[] memory idList2;
        LSSVMPair pair2 = this.setupPair{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)), // asset recipient
            LSSVMPair.PoolType.TRADE,
            delta,
            0, // 0% for trade fee
            spotPrice,
            idList2,
            tokenAmount,
            address(0)
        );
        pair2.transferOwnership{value: 0.1 ether}(address(agreement), "");
        results = factory.getAllPairsForAgreement(address(agreement));
        assertEq(results.length, 2);

        // Remove first pair from agreement
        vm.warp(block.timestamp + 1 days + 1 seconds);
        agreement.reclaimPair(address(pair));

        results = factory.getAllPairsForAgreement(address(agreement));
        assertEq(results.length, 1);
    }

    // Standard Agreement + Agreement Factory tests:

    // Creating a Standard Agreement works as expected, values are as expected
    function test_createAgreementFromFactory() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 royaltyBps = 3;
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, royaltyBps);
        assertEq(newAgreement.agreementFeeRecipient(), agreementFeeRecipient);
        assertEq(newAgreement.getAgreementCost(), ethCost);
        assertEq(newAgreement.getLockDuration(), secDuration);
        assertEq(newAgreement.getFeeSplitBps(), feeSplitBps);
        assertEq(newAgreement.getAgreementRoyaltyBps(), royaltyBps);
        assertEq(IOwnable(address(newAgreement)).owner(), address(this));
        newAgreement.setAgreementFeeRecipient(payable(address(this)));
        assertEq(newAgreement.agreementFeeRecipient(), address(this));
    }

    // A pair can enter a Standard Agreement if authorized
    // Owner can change pair fee within tolerance after entering Agreement
    // Modified royalty is applied after entering Agreement
    function test_enterAgreementForPool() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Check the upfront fee was received
        assertEq(agreementFeeRecipient.balance, ethCost);

        // Check the Agreement has been applied, with the new bps
        (bool isInAgreement, uint96 pairRoyaltyBps) = factory.getAgreementForPair(address(pair));
        assertEq(isInAgreement, true);
        assertEq(pairRoyaltyBps, newRoyaltyBps);

        // Check that the fee address is no longer the pool (i.e. a fee splitter has been deployed)
        require(pair.getFeeRecipient() != address(pair), "Splitter not deployed");

        // Perform a buy for item #1
        (,,, uint256 inputAmount,) = pair.getBuyNFTQuote(1);
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;
        pair.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        uint256 royaltyBalance = getBalance(ROYALTY_RECEIVER);
        assertEq(royaltyBalance, calcRoyalty(inputAmount, newRoyaltyBps));

        // Perform a sell for item #1
        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
        uint256 expectedRoyaltyAmount = calcRoyalty(outputAmount, newRoyaltyBps);
        uint256[] memory specificIdToSell = new uint256[](1);
        specificIdToSell[0] = 1;
        pair.swapNFTsForToken(
            specificIdToSell, outputAmount - expectedRoyaltyAmount, payable(address(this)), false, address(this)
        );
        uint256 secondRoyaltyPayment = getBalance(ROYALTY_RECEIVER) - royaltyBalance;
        assertEq(secondRoyaltyPayment, expectedRoyaltyAmount);

        // Changing the fee to under 20% works
        uint96 newFee = 0.2e18;
        newAgreement.changeFee(address(pair), newFee);
    }

    // Even if an agreement is enabled on the factory contract, the standard agreement
    // requires ownership of the pair to provide a royalty override
    function test_enterAgreementNotPairOwner() public {
        factory.toggleAgreementForCollection(address(agreement), address(test721), true);
        factory.enableAgreementForPair(address(agreement), address(pair));
        assertEq(factory.agreementForPair(address(pair)), address(agreement));

        (bool isInAgreement, uint96 royaltyBps) = agreement.getRoyaltyInfo(address(pair));
        assertEq(isInAgreement, false);
        assertEq(royaltyBps, 0);

        (isInAgreement, royaltyBps) = factory.getAgreementForPair(address(pair));
        assertEq(isInAgreement, false);
        assertEq(royaltyBps, 0);
    }

    // Verify that the only the first receiver receives royalty payments when there is an agreement active
    function test_swapOverrideWithMultipleReceivers() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 500; // 5% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Setup multiple royalty receivers
        address secondReceiver = vm.addr(2);
        address payable[] memory receivers = new address payable[](2);
        receivers[0] = payable(ROYALTY_RECEIVER);
        receivers[1] = payable(secondReceiver);
        uint256[] memory bps = new uint256[](2);
        bps[0] = 750;
        bps[1] = 200;
        TestManifold testManifold = new TestManifold(receivers, bps);
        IRoyaltyRegistry(royaltyEngine.royaltyRegistry()).setRoyaltyLookupAddress(
            address(test721), address(testManifold)
        );

        // Perform a buy for item #1
        (,,, uint256 inputAmount,) = pair.getBuyNFTQuote(1);
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;
        pair.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        // Ensure that the payout is 5% not 7.5%
        assertEq(getBalance(ROYALTY_RECEIVER), calcRoyalty(inputAmount, newRoyaltyBps));
        assertEq(getBalance(secondReceiver), 0);
    }

    // A pair cannot enter into an agreement if the trading fee is too high
    function test_enterAgreementFeeTooHigh() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);

        pair.changeFee(2e17 + 1);

        vm.expectRevert("Fee too high");
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");
    }

    // Changing the price up works (because there are tokens)
    // Changing the price down works (because there are NFTs)
    function test_changeParamsAfterEnteringAgreement() public {
        // Set up sample Agreement
        address payable agreementFeeRecipient = payable(address(123));
        StandardAgreement newAgreement = agreementFactory.createAgreement(agreementFeeRecipient, 0, 1, 2, 1000);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);

        // Opt into the Agreement
        pair.transferOwnership(address(newAgreement), "");

        // Get new params for changing price to buy up
        uint256 percentage = 1.1 * 1e18; // 10%
        (uint128 newSpotPrice, uint128 newDelta) = this.getParamsForAdjustingPriceToBuy(pair, percentage, true);

        // Changing price up works
        newAgreement.changeSpotPriceAndDelta(address(pair), newSpotPrice, newDelta);

        // Get new params for changing price to buy down
        percentage = 0.9 * 1e18; // 10%
        (newSpotPrice, newDelta) = this.getParamsForAdjustingPriceToBuy(pair, percentage, true);

        // Changing price down works
        newAgreement.changeSpotPriceAndDelta(address(pair), newSpotPrice, newDelta);
    }

    // Changing the price up fails (because there are no tokens)
    function testFail_changeBuyPriceUpNoTokens() public {
        // Set up sample Agreement
        address payable agreementFeeRecipient = payable(address(123));
        StandardAgreement newAgreement = agreementFactory.createAgreement(agreementFeeRecipient, 0, 1, 2, 1000);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);

        // Withdraw tokens from pair
        this.withdrawTokens(pair);

        // Opt into the Agreement
        pair.transferOwnership(address(newAgreement), "");

        // Get new params for changing price to buy up
        uint256 percentage = 1.1 * 1e18; // 10%
        (uint128 newSpotPrice, uint128 newDelta) = this.getParamsForAdjustingPriceToBuy(pair, percentage, true);

        // Changing price up should fail because there is no more buy pressure
        newAgreement.changeSpotPriceAndDelta(address(pair), newSpotPrice, newDelta);
    }

    // Changing the price down fails (because there are no NFTs)
    function testFail_changeBuyPriceDownNoNFTs() public {
        // Set up sample Agreement
        address payable agreementFeeRecipient = payable(address(123));
        StandardAgreement newAgreement = agreementFactory.createAgreement(agreementFeeRecipient, 0, 1, 2, 1000);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);

        // Withdraw tokens from pair
        pair.withdrawERC721(IERC721(pair.nft()), idList);

        // Opt into the Agreement
        pair.transferOwnership(address(newAgreement), "");

        // Get new params for changing price to buy up
        uint256 percentage = 0.9 * 1e18; // 10%
        (uint128 newSpotPrice, uint128 newDelta) = this.getParamsForAdjustingPriceToBuy(pair, percentage, true);

        // Changing price down should fail because there is no more nft ivnentory
        newAgreement.changeSpotPriceAndDelta(address(pair), newSpotPrice, newDelta);
    }

    function testFail_changeFeeTooHigh() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Setting new fee to be above 20%
        uint256 newFee = 0.2e18 + 1;
        newAgreement.changeFee(address(pair), uint96(newFee));
    }

    // A pair cannot enter a Standard Agreement if the Agreement is unauthorized
    function testFail_enterAgreementForPoolIfAgreementIsNotAuthHasNoEffect() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 10000; // 10% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");
    }

    // A mock pair cannot enter a Standard Agreement
    function testFail_enterAgreementForMockPool() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);
        mockPair.transferOwnership{value: ethCost}(address(newAgreement), "");
    }

    // Leaving after the expiry date succeeds
    function test_leaveAgreementAfterExpiry() public {
        // Set up basic Agreement
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);

        // Opt into the Agreement
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Skip ahead in time
        skip(secDuration + 1);

        // Attempt to leave the Agreement
        newAgreement.reclaimPair(address(pair));

        // Check that the owner is now set back to caller
        assertEq(pair.owner(), address(this));
        // Check that old pairInfo has been cleared out
        assertEq(newAgreement.getPrevFeeRecipientForPair(address(pair)), address(0));
        // Prev fee recipient defaulted to the pair, so it should still be the pair
        assertEq(pair.getFeeRecipient(), address(pair));
        (bool isInAgreement,) = factory.getAgreementForPair(address(pair));
        assertEq(isInAgreement, false);
    }

    // Leaving after the expiry date succeeds
    function testFail_leaveAgreementAfterExpiryAsDiffCaller() public {
        // Set up basic Agreement
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);

        // Opt into the Agreement
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Skip ahead in time
        skip(secDuration + 1);

        hoax(address(12321));

        // Attempt to leave the Agreement
        newAgreement.reclaimPair(address(pair));

        // Perform a buy for item #1
        (
            ,
            ,
            ,
            /* error*/
            /* new delta */
            /* new spot price*/
            uint256 inputAmount, // protocolFee
            ,
        ) = pair.bondingCurve().getBuyInfo(
            pair.spotPrice(), pair.delta(), 1, pair.fee(), factory.protocolFeeMultiplier()
        );
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;

        // Check test2981
        (address royaltyRecipient, uint256 royaltyAmount) = test2981.royaltyInfo(1, inputAmount);

        // Get before balance
        uint256 startBalance = this.getBalance(royaltyRecipient);

        // Do the swap
        pair.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        // Get after balance
        uint256 afterBalance = this.getBalance(royaltyRecipient);

        // Ensure the right royalty amount was paid
        assertEq(afterBalance - startBalance, royaltyAmount);
    }

    // Leaving before the expiry date fails
    function testFail_leaveAgreementBeforeExpiry() public {
        // Set up basic Agreement
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0 ether;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);

        // Opt into the Agreement
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Attempt to leave the Agreement
        newAgreement.reclaimPair(address(pair));
    }

    // Splitter tests

    // A pair can enter a Standard Agreement if authorized
    function test_splitterHandlesSplits() public {
        // Set the trade fee recipient address
        address payable pairFeeRecipient = payable(address(1));
        pair.changeAssetRecipient(pairFeeRecipient);

        // Set trade fee to be 10%
        pair.changeFee(0.1 ether);

        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 5000; // 50% split
        uint64 newRoyaltyBps = 0; // 0% in bps
        StandardAgreement newAgreement =
            agreementFactory.createAgreement(agreementFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleAgreementForCollection(address(newAgreement), address(test721), true);
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Check that the fee address is no longer the pool (i.e. a fee splitter has been deployed)
        require(pair.getFeeRecipient() != address(pair), "Splitter not deployed");

        // Verify the Splitter has the correct variables
        assertEq(Splitter(pair.getFeeRecipient()).getParentAgreement(), address(newAgreement), "Incorrect parent");
        assertEq(Splitter(pair.getFeeRecipient()).getPairAddressForSplitter(), address(pair), "Incorrect pair");

        // Perform a buy for item #1
        (
            ,
            ,
            ,
            /* error*/
            /* new delta */
            /* new spot price*/
            uint256 inputAmount,
            uint256 tradeFee, // protocolFee
        ) = pair.bondingCurve().getBuyInfo(
            pair.spotPrice(), pair.delta(), 1, pair.fee(), factory.protocolFeeMultiplier()
        );
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;
        pair.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        // Ensure that 2x the trade fee went to the splitter
        address payable splitterAddress = pair.getFeeRecipient();
        uint256 splitterBalance = getBalance(splitterAddress);
        assertEq(splitterBalance, 2 * tradeFee);

        // Withdraw the tokens
        if (factory.isPair(address(pair), ILSSVMPairFactoryLike.PairVariant.ERC721_ETH)) {
            Splitter(splitterAddress).withdrawAllETH();
        } else {
            Splitter(splitterAddress).withdrawAllBaseQuoteTokens();
        }

        // Ensure that the Agreement-set fee recipient received the tokens
        uint256 agreementFeeRecipientBalance = getBalance(agreementFeeRecipient);
        assertEq(agreementFeeRecipientBalance, tradeFee);
        uint256 tradeFeeRecipientBalance = getBalance(pairFeeRecipient);
        assertEq(tradeFeeRecipientBalance, tradeFee);

        // Do two swaps in succession
        // Perform a buy for item #2 and #3
        (
            ,
            ,
            ,
            /* error*/
            /* new delta */
            /* new spot price*/
            inputAmount,
            tradeFee,
        ) = pair.bondingCurve().getBuyInfo( // protocolFee
        pair.spotPrice(), pair.delta(), 2, pair.fee(), factory.protocolFeeMultiplier());
        specificIdToBuy = new uint256[](2);
        specificIdToBuy[0] = 2;
        specificIdToBuy[1] = 3;
        pair.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        // Ensure that 2x the trade fee went to the splitter
        splitterAddress = pair.getFeeRecipient();
        splitterBalance = getBalance(splitterAddress);
        assertEq(splitterBalance, 2 * tradeFee);
    }
}
