// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {IOwnable} from "../interfaces/IOwnable.sol";
import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {IERC1155Mintable} from "../interfaces/IERC1155Mintable.sol";
import {ILSSVMPairFactoryLike} from "../../ILSSVMPairFactoryLike.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {CurveErrorCodes} from "../../bonding-curves/CurveErrorCodes.sol";

import {StandardSettings} from "../../settings/StandardSettings.sol";
import {StandardSettingsFactory} from "../../settings/StandardSettingsFactory.sol";
import {Splitter} from "../../settings/Splitter.sol";

import {Test20} from "../../mocks/Test20.sol";
import {Test721} from "../../mocks/Test721.sol";
import {Test1155} from "../../mocks/Test1155.sol";
import {TestManifold} from "../../mocks/TestManifold.sol";
import {MockPair} from "../../mocks/MockPair.sol";

abstract contract SettingsE2E is Test, ERC721Holder, ERC1155Holder, ConfigurableWithRoyalties {
    uint128 delta = 1.1 ether;
    uint128 spotPrice = 20 ether;
    uint256 tokenAmount = 100 ether;
    uint256 numItems = 3;
    uint256 settingsFee = 0.1 ether;
    uint64 settingsLockup = 1 days;
    uint256[] idList;
    ERC2981 test2981;
    IERC721 test721;
    IERC721 test721Other;
    IERC1155Mintable test1155;
    ERC20 testERC20;
    ICurve bondingCurve;
    LSSVMPairFactory factory;
    address payable constant feeRecipient = payable(address(69));
    LSSVMPair pair721;
    LSSVMPair pair1155;
    MockPair mockPair;
    RoyaltyEngine royaltyEngine;
    StandardSettingsFactory settingsFactory;
    StandardSettings settings;

    error BondingCurveError(CurveErrorCodes.Error error);

    function setUp() public {
        bondingCurve = setupCurve();
        test721 = setup721();
        test1155 = setup1155();
        test2981 = setup2981();
        test721Other = new Test721();
        royaltyEngine = setupRoyaltyEngine();

        // Set a royalty override
        IRoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(test721), address(test2981));

        // Set up the pair factory
        factory = setupFactory(royaltyEngine, feeRecipient);
        factory.setBondingCurveAllowed(bondingCurve, true);
        test721.setApprovalForAll(address(factory), true);
        test1155.setApprovalForAll(address(factory), true);

        // Mint IDs from 1 to numItems to the caller, to deposit into the pair
        for (uint256 i = 1; i <= numItems; i++) {
            IERC721Mintable(address(test721)).mint(address(this), i);
            idList.push(i);
        }
        pair721 = this.setupPairERC721{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)), // asset recipient
            LSSVMPair.PoolType.TRADE,
            modifyDelta(uint64(delta)),
            0, // 0% for trade fee
            spotPrice,
            idList,
            tokenAmount,
            address(0)
        );
        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair721), 1 ether);
        test721.setApprovalForAll(address(pair721), true);
        testERC20.approve(address(pair721), 10000 ether);

        test1155.mint(address(this), 88, 5);
        pair1155 = this.setupPairERC1155{value: modifyInputAmount(tokenAmount)}(
            CreateERC1155PairParams(
                factory,
                test1155,
                bondingCurve,
                payable(address(0)),
                LSSVMPair.PoolType.TRADE,
                modifyDelta(uint64(delta)),
                0,
                spotPrice,
                88,
                5,
                tokenAmount,
                address(0)
            )
        );
        test1155.setApprovalForAll(address(pair1155), true);

        // Settings setup
        Splitter splitterImplementation = new Splitter();
        StandardSettings settingsImplementation = new StandardSettings(
            splitterImplementation,
            factory
        );
        settingsFactory = new StandardSettingsFactory(
            settingsImplementation
        );

        settings = settingsFactory.createSettings(feeRecipient, settingsFee, settingsLockup, 5, 500);
        mockPair = new MockPair();
        vm.label(address(mockPair), "MockPair");
    }

    // Pair Factory permissions with adding/removing Settings and toggling override royalty bps for pools

    // An authorized caller can correctly add/remove an Settings on the factory
    function test_addSettingsAsAuth() public {
        address settingsAddress = address(69420);
        factory.toggleSettingsForCollection(settingsAddress, address(test721), true);
        assertEq(factory.settingsForCollection(address(test721), settingsAddress), true);
        factory.toggleSettingsForCollection(settingsAddress, address(test721), false);
        assertEq(factory.settingsForCollection(address(test721), settingsAddress), false);
    }

    // An unauthorized caller cannot add/remove an Settings on the factory
    function test_addSettingsAsNotAuth() public {
        IOwnable(address(test721)).transferOwnership(address(12345));
        vm.expectRevert("Unauthorized caller");
        factory.toggleSettingsForCollection(address(1), address(test721), true);

        vm.expectRevert("Unauthorized caller");
        factory.toggleSettingsForCollection(address(1), address(test721), false);
    }

    function test_enableSettingsForPair() public {
        factory.toggleSettingsForCollection(address(settings), address(test721), true);

        // This call will trigger the callback to call enableSettingsForPair on the factory
        pair721.transferOwnership{value: 0.1 ether}(address(settings), "");
        assertEq(factory.settingsForPair(address(pair721)), address(settings));
        (bool settingsEnabled, uint96 royaltyBps) = factory.getSettingsForPair(address(pair721));
        assertEq(settingsEnabled, true);
        assertEq(royaltyBps, 500);

        // Make sure the sell quote has the overridden royalty rate
        (,,, uint256 sellPrice,,) = pair721.bondingCurve().getSellInfo(spotPrice, modifyDelta(uint64(delta)), 1, 0, 0);
        (,,, uint256 outputAmount,,) = pair721.getSellNFTQuote(1, 1);
        assertEq(outputAmount, sellPrice - calcRoyalty(sellPrice, 500));
    }

    function test_enableSettingsForPairIdempotent() public {
        factory.toggleSettingsForCollection(address(settings), address(test721), true);

        // First call will be done directly on the factory
        factory.enableSettingsForPair(address(settings), address(pair721));
        assertEq(factory.settingsForPair(address(pair721)), address(settings));

        // Second call will also make a call to the factory due to the callback
        pair721.transferOwnership{value: 0.1 ether}(address(settings), "");
        assertEq(factory.settingsForPair(address(pair721)), address(settings));
    }

    function test_enableSettingsForPairNotPairOwner() public {
        factory.toggleSettingsForCollection(address(this), address(test721Other), true);
        vm.expectRevert("Msg sender is not pair owner");
        vm.prank(vm.addr(1));
        factory.enableSettingsForPair(address(this), address(pair721));
    }

    function test_enableSettingsForPairSettingsNotEnabled() public {
        vm.expectRevert("Settings not enabled for collection");
        factory.enableSettingsForPair(address(settings), address(pair721));
    }

    function test_enableSettingsForPairInvalidPair() public {
        vm.expectRevert(bytes(""));
        factory.enableSettingsForPair(address(this), address(this));
    }

    function test_disableSettingsForPair() public {
        factory.toggleSettingsForCollection(address(settings), address(test721), true);
        pair721.transferOwnership{value: 0.1 ether}(address(settings), "");

        // Cannot reclaim pair until lockup period has passed
        vm.expectRevert("Lockup not over");
        settings.reclaimPair(address(pair721));

        // Move forward in time so lockup period is over
        vm.warp(block.timestamp + 1 days + 1 seconds);

        settings.reclaimPair(address(pair721));
        assertEq(factory.settingsForPair(address(pair721)), address(0));
        (bool settingsEnabled, uint96 royaltyBps) = factory.getSettingsForPair(address(pair721));
        assertEq(settingsEnabled, false);
        assertEq(royaltyBps, 0);
    }

    function test_reclaimPairBeforeLockupAsOwner() public {
        factory.toggleSettingsForCollection(address(settings), address(test721), true);

        address newOwner = address(12345);
        pair721.transferOwnership(newOwner, "");

        // Give the new owner enough funds to opt into the settings
        vm.deal(newOwner, 10 ether);

        // Pretend to be the new owner
        vm.prank(newOwner);
        pair721.transferOwnership{value: 0.1 ether}(address(settings), "");

        // Reclaim the pair as the settings owner
        settings.reclaimPair(address(pair721));
        assertEq(factory.settingsForPair(address(pair721)), address(0));
        (bool settingsEnabled, uint96 royaltyBps) = factory.getSettingsForPair(address(pair721));
        assertEq(settingsEnabled, false);
        assertEq(royaltyBps, 0);
        assertEq(pair721.owner(), newOwner);
    }

    function test_disableSettingsForPairNotPair() public {
        vm.expectRevert(bytes(""));
        factory.disableSettingsForPair(address(this), address(this));
    }

    function test_disableSettingsForPairNotEnabled() public {
        vm.expectRevert("Settings not enabled for pair");
        factory.disableSettingsForPair(address(settings), address(pair721));
    }

    function test_disableSettingsNotPairOwner() public {
        factory.toggleSettingsForCollection(address(settings), address(test721), true);
        pair721.transferOwnership{value: 0.1 ether}(address(settings), "");

        vm.expectRevert("Msg sender is not pair owner");
        factory.disableSettingsForPair(address(settings), address(pair721));
    }

    function test_getAllPairsForSettings() public {
        address[] memory results = factory.getAllPairsForSettings(address(settings));
        assertEq(results.length, 0);

        // Add pair to settings
        factory.toggleSettingsForCollection(address(settings), address(test721), true);
        pair721.transferOwnership{value: 0.1 ether}(address(settings), "");

        results = factory.getAllPairsForSettings(address(settings));
        assertEq(results.length, 1);
        assertEq(results[0], address(pair721));

        // Add another pair to settings
        uint256[] memory idList2;
        LSSVMPair pair2 = this.setupPairERC721{value: modifyInputAmount(tokenAmount)}(
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
        pair2.transferOwnership{value: 0.1 ether}(address(settings), "");
        results = factory.getAllPairsForSettings(address(settings));
        assertEq(results.length, 2);

        // Remove first pair from settings
        vm.warp(block.timestamp + 1 days + 1 seconds);
        settings.reclaimPair(address(pair721));

        results = factory.getAllPairsForSettings(address(settings));
        assertEq(results.length, 1);
    }

    // Standard Settings + Settings Factory tests:

    // Creating a Standard Settings works as expected, values are as expected
    function test_createSettingsFromFactory() public {
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 royaltyBps = 3;
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, royaltyBps);
        assertEq(newSettings.settingsFeeRecipient(), settingsFeeRecipient);
        assertEq(newSettings.getSettingsCost(), ethCost);
        assertEq(newSettings.getLockDuration(), secDuration);
        assertEq(newSettings.getFeeSplitBps(), feeSplitBps);
        assertEq(newSettings.getSettingsRoyaltyBps(), royaltyBps);
        assertEq(IOwnable(address(newSettings)).owner(), address(this));
        newSettings.setSettingsFeeRecipient(payable(address(this)));
        assertEq(newSettings.settingsFeeRecipient(), address(this));
    }

    // A pair can enter a StandardSettings if authorized
    // Owner can change pair fee within tolerance after enabling Settings
    // Modified royalty is applied after enabling Settings
    function test_applySettingsForPool() public {
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");

        // Check the upfront fee was received
        assertEq(settingsFeeRecipient.balance, ethCost);

        // Check the Settings has been applied, with the new bps
        (bool settingsEnabled, uint96 pairRoyaltyBps) = factory.getSettingsForPair(address(pair721));
        assertEq(settingsEnabled, true);
        assertEq(pairRoyaltyBps, newRoyaltyBps);

        // Check that the fee address is no longer the pool (i.e. a fee splitter has been deployed)
        require(pair721.getFeeRecipient() != address(pair721), "Splitter not deployed");

        // Perform a buy for item #1
        (,,, uint256 inputAmount,) = pair721.getBuyNFTQuote(1);
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;
        pair721.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        uint256 royaltyBalance = getBalance(ROYALTY_RECEIVER);
        assertEq(royaltyBalance, calcRoyalty(inputAmount, newRoyaltyBps));

        // Perform a sell for item #1
        uint256[] memory specificIdToSell = new uint256[](1);
        specificIdToSell[0] = 1;
        (,,, uint256 outputAmount,, uint256 expectedRoyaltyAmount) = pair721.getSellNFTQuote(specificIdToSell[0], 1);
        pair721.swapNFTsForToken(specificIdToSell, outputAmount, payable(address(this)), false, address(this));
        uint256 secondRoyaltyPayment = getBalance(ROYALTY_RECEIVER) - royaltyBalance;
        assertEq(secondRoyaltyPayment, expectedRoyaltyAmount);

        // Changing the fee to under 20% works
        uint96 newFee = 0.2e18;
        newSettings.changeFee(address(pair721), newFee);
    }

    // Even if an settings is enabled on the factory contract, the standard settings
    // requires ownership of the pair to provide a royalty override
    function test_enterSettingsNotPairOwner() public {
        factory.toggleSettingsForCollection(address(settings), address(test721), true);
        factory.enableSettingsForPair(address(settings), address(pair721));
        assertEq(factory.settingsForPair(address(pair721)), address(settings));

        (bool settingsEnabled, uint96 royaltyBps) = settings.getRoyaltyInfo(address(pair721));
        assertEq(settingsEnabled, false);
        assertEq(royaltyBps, 0);

        (settingsEnabled, royaltyBps) = factory.getSettingsForPair(address(pair721));
        assertEq(settingsEnabled, false);
        assertEq(royaltyBps, 0);
    }

    // Verify that the only the first receiver receives royalty payments when there is an settings active
    function test_swapOverrideWithMultipleReceivers() public {
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 500; // 5% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");

        // Setup multiple royalty receivers
        address secondReceiver = vm.addr(2);
        address payable[] memory receivers = new address payable[](2);
        receivers[0] = payable(ROYALTY_RECEIVER);
        receivers[1] = payable(secondReceiver);
        uint256[] memory bps = new uint256[](2);
        bps[0] = 750;
        bps[1] = 200;
        TestManifold testManifold = new TestManifold(receivers, bps);
        IRoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(
            address(test721), address(testManifold)
        );

        // Perform a buy for item #1
        (,,, uint256 inputAmount,) = pair721.getBuyNFTQuote(1);
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;
        pair721.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        // Ensure that the payout is 5% not 7.5%
        assertEq(getBalance(ROYALTY_RECEIVER), calcRoyalty(inputAmount, newRoyaltyBps));
        assertEq(getBalance(secondReceiver), 0);
    }

    // A pair cannot enter into an settings if the trading fee is too high
    function test_enterSettingsFeeTooHigh() public {
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        pair721.changeFee(2e17 + 1);

        vm.expectRevert("Fee too high");
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");
    }

    // Changing the price up works (because there are tokens)
    // Changing the price down works (because there are NFTs)
    function test_changeParamsAfterEnteringSettings() public {
        // Set up sample Settings
        address payable settingsFeeRecipient = payable(address(123));
        StandardSettings newSettings = settingsFactory.createSettings(settingsFeeRecipient, 0, 1, 2, 1000);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        // Opt into the Settings
        pair721.transferOwnership(address(newSettings), "");

        // Get new params for changing price to buy up
        uint256 percentage = 1.1 * 1e18; // 10%
        (uint128 newSpotPrice, uint128 newDelta) = this.getParamsForAdjustingPriceToBuy(pair721, percentage, true);

        // Changing price up works
        newSettings.changeSpotPriceAndDelta(address(pair721), newSpotPrice, newDelta, 1);

        // Get new params for changing price to buy down
        percentage = 0.9 * 1e18; // 10%
        (newSpotPrice, newDelta) = this.getParamsForAdjustingPriceToBuy(pair721, percentage, true);

        // Changing price down works
        newSettings.changeSpotPriceAndDelta(address(pair721), newSpotPrice, newDelta, 1);
    }

    function test_changeParamsAfterEnteringSettings_ERC1155() public {
        // Set up sample Settings
        address payable settingsFeeRecipient = payable(address(123));
        StandardSettings newSettings = settingsFactory.createSettings(settingsFeeRecipient, 0, 1, 2, 1000);
        factory.toggleSettingsForCollection(address(newSettings), address(test1155), true);

        // Opt into the Settings
        pair1155.transferOwnership(address(newSettings), "");

        // Get new params for changing price to buy up
        uint256 percentage = 1.1 * 1e18; // 10%
        (uint128 newSpotPrice, uint128 newDelta) = this.getParamsForAdjustingPriceToBuy(pair1155, percentage, true);

        // Changing price up works
        newSettings.changeSpotPriceAndDelta(address(pair1155), newSpotPrice, newDelta, 1);

        // Get new params for changing price to buy down
        percentage = 0.9 * 1e18; // 10%
        (newSpotPrice, newDelta) = this.getParamsForAdjustingPriceToBuy(pair1155, percentage, true);

        // Changing price down works
        newSettings.changeSpotPriceAndDelta(address(pair1155), newSpotPrice, newDelta, 1);
    }

    // Changing the price up fails (because there are no tokens)
    function testFail_changeBuyPriceUpNoTokens() public {
        // Set up sample Settings
        address payable settingsFeeRecipient = payable(address(123));
        StandardSettings newSettings = settingsFactory.createSettings(settingsFeeRecipient, 0, 1, 2, 1000);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        // Withdraw tokens from pair
        this.withdrawTokens(pair721);

        // Opt into the Settings
        pair721.transferOwnership(address(newSettings), "");

        // Get new params for changing price to buy up
        uint256 percentage = 1.1 * 1e18; // 10%
        (uint128 newSpotPrice, uint128 newDelta) = this.getParamsForAdjustingPriceToBuy(pair721, percentage, true);

        // Changing price up should fail because there is no more buy pressure
        newSettings.changeSpotPriceAndDelta(address(pair721), newSpotPrice, newDelta, 1);
    }

    // Changing the price down fails (because there are no NFTs)
    function testFail_changeBuyPriceDownNoNFTs() public {
        // Set up sample Settings
        address payable settingsFeeRecipient = payable(address(123));
        StandardSettings newSettings = settingsFactory.createSettings(settingsFeeRecipient, 0, 1, 2, 1000);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        // Withdraw tokens from pair
        pair721.withdrawERC721(IERC721(pair721.nft()), idList);

        // Opt into the Settings
        pair721.transferOwnership(address(newSettings), "");

        // Get new params for changing price to buy up
        uint256 percentage = 0.9 * 1e18; // 10%
        (uint128 newSpotPrice, uint128 newDelta) = this.getParamsForAdjustingPriceToBuy(pair721, percentage, true);

        // Changing price down should fail because there is no more nft ivnentory
        newSettings.changeSpotPriceAndDelta(address(pair721), newSpotPrice, newDelta, 1);
    }

    function testFail_changeFeeTooHigh() public {
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");

        // Setting new fee to be above 20%
        uint256 newFee = 0.2e18 + 1;
        newSettings.changeFee(address(pair721), uint96(newFee));
    }

    // A pair cannot enter a Standard Settings if the Settings are unauthorized
    function testFail_enterSettingsForPoolIfSettingsAreNotAuthHasNoEffect() public {
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 10000; // 10% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");
    }

    // A mock pair cannot enter a Standard Settings
    function test_cannotEnterSettingsForMockPool() public {
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);
        vm.expectRevert(bytes("Pair verification failed"));
        mockPair.transferOwnership{value: ethCost}(address(newSettings), "");
    }

    // Leaving after the expiry date succeeds
    function test_removeSettingsAfterExpiry() public {
        // Set up basic Settings
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        // Opt into the Settings
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");

        // Skip ahead in time
        skip(secDuration + 1);

        // Attempt to leave the Settings
        newSettings.reclaimPair(address(pair721));

        // Check that the owner is now set back to caller
        assertEq(pair721.owner(), address(this));
        // Check that old pairInfo has been cleared out
        assertEq(newSettings.getPrevFeeRecipientForPair(address(pair721)), address(0));
        // Prev fee recipient defaulted to the pair, so it should still be the pair
        assertEq(pair721.getFeeRecipient(), address(pair721));
        (bool settingsEnabled,) = factory.getSettingsForPair(address(pair721));
        assertEq(settingsEnabled, false);
    }

    // Leaving after the expiry date succeeds
    function testFail_leaveSettingsAfterExpiryAsDiffCaller() public {
        // Set up basic Settings
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        // Opt into the Settings
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");

        // Skip ahead in time
        skip(secDuration + 1);

        hoax(address(12321));

        // Attempt to leave the Settings
        newSettings.reclaimPair(address(pair721));

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
        ) = pair721.bondingCurve().getBuyInfo(
            pair721.spotPrice(), pair721.delta(), 1, pair721.fee(), factory.protocolFeeMultiplier()
        );
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;

        // Check test2981
        (address royaltyRecipient, uint256 royaltyAmount) = test2981.royaltyInfo(1, inputAmount);

        // Get before balance
        uint256 startBalance = this.getBalance(royaltyRecipient);

        // Do the swap
        pair721.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        // Get after balance
        uint256 afterBalance = this.getBalance(royaltyRecipient);

        // Ensure the right royalty amount was paid
        assertEq(afterBalance - startBalance, royaltyAmount);
    }

    // Leaving before the expiry date fails
    function testFail_leaveSettingsBeforeExpiry() public {
        // Set up basic Settings
        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0 ether;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        // Opt into the Settings
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");

        // Attempt to leave the Settings
        newSettings.reclaimPair(address(pair721));
    }

    // Splitter tests

    // A pair can enter a Standard Settings if authorized
    function test_splitterHandlesSplits() public {
        // Set the trade fee recipient address
        address payable pairFeeRecipient = payable(address(1));
        pair721.changeAssetRecipient(pairFeeRecipient);

        // Set trade fee to be 10%
        pair721.changeFee(0.1 ether);

        address payable settingsFeeRecipient = payable(address(123));
        uint256 ethCost = 0 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 5000; // 50% split
        uint64 newRoyaltyBps = 0; // 0% in bps
        StandardSettings newSettings =
            settingsFactory.createSettings(settingsFeeRecipient, ethCost, secDuration, feeSplitBps, newRoyaltyBps);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);
        pair721.transferOwnership{value: ethCost}(address(newSettings), "");

        // Check that the fee address is no longer the pool (i.e. a fee splitter has been deployed)
        require(pair721.getFeeRecipient() != address(pair721), "Splitter not deployed");

        // Verify the Splitter has the correct variables
        assertEq(Splitter(pair721.getFeeRecipient()).getParentSettings(), address(newSettings), "Incorrect parent");
        assertEq(Splitter(pair721.getFeeRecipient()).getPairAddressForSplitter(), address(pair721), "Incorrect pair");

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
        ) = pair721.bondingCurve().getBuyInfo(
            pair721.spotPrice(), pair721.delta(), 1, pair721.fee(), factory.protocolFeeMultiplier()
        );
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;
        pair721.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        // Ensure that 2x the trade fee went to the splitter
        address payable splitterAddress = pair721.getFeeRecipient();
        uint256 splitterBalance = getBalance(splitterAddress);
        assertEq(splitterBalance, 2 * tradeFee);

        // Withdraw the tokens
        if (factory.getPairTokenType(address(pair721)) == ILSSVMPairFactoryLike.PairTokenType.ETH) {
            Splitter(splitterAddress).withdrawAllETHInSplitter();
        } else {
            Splitter(splitterAddress).withdrawAllBaseQuoteTokens();
        }

        // Ensure that the Settings-set fee recipient received the tokens
        uint256 settingsFeeRecipientBalance = getBalance(settingsFeeRecipient);
        assertEq(settingsFeeRecipientBalance, tradeFee);
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
        ) = pair721.bondingCurve().getBuyInfo( // protocolFee
        pair721.spotPrice(), pair721.delta(), 2, pair721.fee(), factory.protocolFeeMultiplier());
        specificIdToBuy = new uint256[](2);
        specificIdToBuy[0] = 2;
        specificIdToBuy[1] = 3;
        pair721.swapTokenForSpecificNFTs{value: this.modifyInputAmount(inputAmount)}(
            specificIdToBuy, inputAmount, address(this), false, address(this)
        );

        // Ensure that 2x the trade fee went to the splitter
        splitterAddress = pair721.getFeeRecipient();
        splitterBalance = getBalance(splitterAddress);
        assertEq(splitterBalance, 2 * tradeFee);
    }
}
