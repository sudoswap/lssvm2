// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";

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
import {CurveErrorCodes} from "../../bonding-curves/CurveErrorCodes.sol";

import {StandardSettings} from "../../settings/StandardSettings.sol";
import {StandardSettingsFactory} from "../../settings/StandardSettingsFactory.sol";
import {Splitter} from "../../settings/Splitter.sol";

import {Test20} from "../../mocks/Test20.sol";
import {Test721} from "../../mocks/Test721.sol";
import {MockCurve} from "../../mocks/MockCurve.sol";
import {TestManifold} from "../../mocks/TestManifold.sol";
import {UsingMockCurve} from "../../test/mixins/UsingMockCurve.sol";
import {UsingETH} from "../mixins/UsingETH.sol";

contract SettingsWithMockCurve is Test, ERC721Holder, ConfigurableWithRoyalties, UsingMockCurve, UsingETH {
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
    ICurve bondingCurve;
    LSSVMPairFactory factory;
    address payable constant feeRecipient = payable(address(69));
    LSSVMPair pair721;
    RoyaltyEngine royaltyEngine;
    StandardSettingsFactory settingsFactory;
    StandardSettings settings;
    MockCurve mockCurve;

    error BondingCurveError(CurveErrorCodes.Error error);

    function setUp() public {
        bondingCurve = setupCurve();
        mockCurve = MockCurve(address(bondingCurve));
        test721 = setup721();
        test2981 = setup2981();
        test721Other = new Test721();
        royaltyEngine = setupRoyaltyEngine();

        // Set a royalty override
        IRoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(test721), address(test2981));

        // Set up the pair factory
        factory = setupFactory(royaltyEngine, feeRecipient);
        factory.setBondingCurveAllowed(bondingCurve, true);
        test721.setApprovalForAll(address(factory), true);

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
        test721.setApprovalForAll(address(pair721), true);

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
    }

    function test_changeSettingsSpotPriceBuyCurveError() public {
        // Error with INVALID_NUMITEMS
        mockCurve.setBuyError(1);

        // Set up sample Settings
        address payable settingsFeeRecipient = payable(address(123));
        StandardSettings newSettings = settingsFactory.createSettings(settingsFeeRecipient, 0, 1, 2, 1000);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        // Opt into the Settings
        pair721.transferOwnership(address(newSettings), "");

        // Changing price up won't work due to curve error on getBuyInfo
        vm.expectRevert(abi.encodeWithSelector(BondingCurveError.selector, 1));
        newSettings.changeSpotPriceAndDelta(address(pair721), 100, 10, 1);
    }

    function test_changeSettingsSpotPriceSellCurveError() public {
        // Error with SPOT_PRICE_OVERFLOW
        mockCurve.setSellError(2);

        // Set up sample Settings
        address payable settingsFeeRecipient = payable(address(123));
        StandardSettings newSettings = settingsFactory.createSettings(settingsFeeRecipient, 0, 1, 2, 1000);
        factory.toggleSettingsForCollection(address(newSettings), address(test721), true);

        // Opt into the Settings
        pair721.transferOwnership(address(newSettings), "");

        // Changing price up won't work due to curve error on getSellInfo
        vm.expectRevert(abi.encodeWithSelector(BondingCurveError.selector, 2));
        newSettings.changeSpotPriceAndDelta(address(pair721), spotPrice, 10, 1);
    }
}
