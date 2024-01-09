// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Test20} from "../../mocks/Test20.sol";
import {LSSVMPair} from "../../LSSVMPair.sol";
import {Test721} from "../../mocks/Test721.sol";
import {MockSettings} from "../../mocks/MockSettings.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {Test1155} from "../../mocks/Test1155.sol";
import {Test2981} from "../../mocks/Test2981.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMPairERC721} from "../../erc721/LSSVMPairERC721.sol";
import {TestPairManager} from "../../mocks/TestPairManager.sol";
import {TestPairManager2} from "../../mocks/TestPairManager2.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {IERC1155Mintable} from "../interfaces/IERC1155Mintable.sol";
import {ILSSVMPairFactoryLike} from "../../ILSSVMPairFactoryLike.sol";
import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";
import {IOwnershipTransferReceiver} from "../../lib/IOwnershipTransferReceiver.sol";
import {MockOwnershipTransferReceiver} from "../../mocks/MockOwnershipTransferReceiver.sol";

error Ownable_NotOwner();

abstract contract PairAndFactory is Test, ERC721Holder, ERC1155Holder, ConfigurableWithRoyalties {
    event NFTWithdrawal(uint256 numNFTs);

    uint128 delta = 1.1 ether;
    uint128 spotPrice = 1 ether;
    uint256 tokenAmount = 10 ether;
    uint256 numItems = 2;
    uint256 startingId;
    uint256[] idList;
    IERC721 test721;
    IERC1155Mintable test1155;
    ERC20 testERC20;
    ICurve bondingCurve;
    LSSVMPairFactory factory;
    address payable constant feeRecipient = payable(address(69));
    uint256 constant protocolFeeMultiplier = 3e15;
    LSSVMPair pair;
    LSSVMPair pair1155;
    TestPairManager pairManager;
    TestPairManager2 pairManager2;

    RoyaltyEngine royaltyEngine;

    function setUp() public {
        bondingCurve = setupCurve();
        test721 = setup721();
        test1155 = setup1155();
        royaltyEngine = setupRoyaltyEngine();
        factory = setupFactory(royaltyEngine, feeRecipient, protocolFeeMultiplier);
        factory.setBondingCurveAllowed(bondingCurve, true);
        test721.setApprovalForAll(address(factory), true);
        test1155.setApprovalForAll(address(factory), true);

        for (uint256 i = 1; i <= numItems; i++) {
            IERC721Mintable(address(test721)).mint(address(this), i);
            idList.push(i);
        }
        test1155.mint(address(this), startingId, numItems);

        pair = this.setupPairERC721{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            delta,
            0,
            spotPrice,
            idList,
            tokenAmount,
            address(0)
        );

        pair1155 = this.setupPairERC1155{value: modifyInputAmount(tokenAmount)}(
            CreateERC1155PairParams(
                factory,
                test1155,
                bondingCurve,
                payable(address(0)),
                LSSVMPair.PoolType.TRADE,
                delta,
                0,
                spotPrice,
                startingId,
                numItems,
                tokenAmount,
                address(0),
                address(0)
            )
        );

        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair), 1 ether);
        IMintable(address(testERC20)).mint(address(pair1155), 1 ether);
        pairManager = new TestPairManager();
        pairManager2 = new TestPairManager2();
    }

    function testGas_basicDeploy() public {
        uint256[] memory empty;
        this.setupPairERC721{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            delta,
            0,
            spotPrice,
            empty,
            tokenAmount,
            address(0)
        );
    }

    /**
     * Test LSSVMPair owner functions
     */

    function test_defaultAssetRecipientForPoolERC721() public {
        uint256[] memory empty;
        assertEq(pair.getAssetRecipient(), address(pair)); // TRADE pools will always recieve the asset themselves
        LSSVMPair nftPool = this.setupPairERC721{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)),
            LSSVMPair.PoolType.NFT,
            delta,
            0,
            spotPrice,
            empty,
            tokenAmount,
            address(0)
        );
        assertEq(nftPool.getAssetRecipient(), nftPool.owner());
        LSSVMPair tokenPool = this.setupPairERC721{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TOKEN,
            delta,
            0,
            spotPrice,
            empty,
            tokenAmount,
            address(0)
        );
        assertEq(tokenPool.getAssetRecipient(), tokenPool.owner());
    }

    function test_defaultAssetRecipientForPoolERC1155() public {
        assertEq(pair1155.getAssetRecipient(), address(pair1155)); // TRADE pools will always recieve the asset themselves
        LSSVMPair nftPool = this.setupPairERC1155(
            CreateERC1155PairParams(
                factory,
                test1155,
                bondingCurve,
                payable(address(0)),
                LSSVMPair.PoolType.NFT,
                delta,
                0,
                spotPrice,
                0,
                0,
                modifyInputAmount(tokenAmount),
                address(0),
                address(0)
            )
        );
        assertEq(nftPool.getAssetRecipient(), nftPool.owner());
        LSSVMPair tokenPool = this.setupPairERC1155(
            CreateERC1155PairParams(
                factory,
                test1155,
                bondingCurve,
                payable(address(0)),
                LSSVMPair.PoolType.TOKEN,
                delta,
                0,
                spotPrice,
                0,
                0,
                modifyInputAmount(tokenAmount),
                address(0),
                address(0)
            )
        );
        assertEq(tokenPool.getAssetRecipient(), tokenPool.owner());
    }

    function test_defaultFeeRecipientERC721() public {
        assertEq(pair.getFeeRecipient(), address(pair));
    }

    function test_defaultFeeRecipientERC1155() public {
        assertEq(pair1155.getFeeRecipient(), address(pair1155));
    }

    function test_transferOwnershipERC721() public {
        pair.transferOwnership(payable(address(2)), "");
        assertEq(pair.owner(), address(2));
    }

    function test_transferOwnershipERC1155() public {
        pair1155.transferOwnership(payable(address(2)), "");
        assertEq(pair1155.owner(), address(2));
    }

    function test_transferOwnershipToNonCallbackContractERC721() public {
        pair.transferOwnership(payable(address(pair)), "");
        assertEq(pair.owner(), address(pair));
    }

    function test_transferOwnershipToNonCallbackContractERC1155() public {
        pair1155.transferOwnership(payable(address(pair1155)), "");
        assertEq(pair1155.owner(), address(pair1155));
    }

    function test_transferOwnershipCallbackERC721() public {
        pair.transferOwnership(address(pairManager), "");
        assertEq(pairManager.prevOwner(), address(this));
    }

    function test_transferOwnershipCallbackERC1155() public {
        pair1155.transferOwnership(address(pairManager), "");
        assertEq(pairManager.prevOwner(), address(this));
    }

    function test_transferCallbackWithArgsERC721() public {
        pair.transferOwnership(address(pairManager2), abi.encode(42));
        assertEq(pairManager2.value(), 42);
    }

    function test_transferCallbackWithArgsERC1155() public {
        pair1155.transferOwnership(address(pairManager2), abi.encode(42));
        assertEq(pairManager2.value(), 42);
    }

    function testGas_transferNoCallbackERC721() public {
        pair.transferOwnership(address(pair), "");
    }

    function testGas_transferNoCallbackERC1155() public {
        pair1155.transferOwnership(address(pair1155), "");
    }

    function testFail_transferOwnershipERC721() public {
        pair.transferOwnership(address(1000), "");
        pair.transferOwnership(payable(address(2)), "");
    }

    function testFail_transferOwnershipERC1155() public {
        pair1155.transferOwnership(address(1000), "");
        pair1155.transferOwnership(payable(address(2)), "");
    }

    function test_rescueTokensERC721() public {
        pair.withdrawERC721(test721, idList);
        pair.withdrawERC20(testERC20, 1 ether);

        // Check the id list is now empty
        assertEq(LSSVMPairERC721(address(pair)).numIdsHeld(), 0);
        uint256[] memory storedIds =
            LSSVMPairERC721(address(pair)).getIds(0, LSSVMPairERC721(address(pair)).numIdsHeld());
        assertEq(storedIds.length, 0);
    }

    function test_rescueTokensERC1155() public {
        uint256 id = 0;
        test1155.mint(address(pair1155), id, 2);
        assertEq(test1155.balanceOf(address(this), id), 0);

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amount = new uint256[](1);
        amount[0] = 2;

        vm.expectEmit(true, true, true, true);
        emit NFTWithdrawal(2);
        pair1155.withdrawERC1155(test1155, ids, amount);
        assertEq(test1155.balanceOf(address(this), id), 2);
        pair1155.withdrawERC20(testERC20, 1 ether);
    }

    function testFail_tradePoolChangeFeePastMaxERC721() public {
        pair.changeFee(100 ether);
    }

    function testFail_tradePoolChangeFeePastMaxERC1155() public {
        pair1155.changeFee(100 ether);
    }

    function test_verifyPoolParamsERC721() public {
        // verify pair variables
        assertEq(address(pair.nft()), address(test721));
        assertEq(address(pair.bondingCurve()), address(bondingCurve));
        assertEq(uint256(pair.poolType()), uint256(LSSVMPair.PoolType.TRADE));
        assertEq(pair.delta(), delta);
        assertEq(pair.spotPrice(), spotPrice);
        assertEq(pair.owner(), address(this));
        assertEq(pair.fee(), 0);
        assertEq(pair.getAssetRecipient(), address(pair));
        assertEq(getBalance(address(pair)), tokenAmount);

        // verify NFT ownership
        assertEq(test721.ownerOf(1), address(pair));
    }

    function test_verifyPoolParamsERC1155() public {
        // verify pair variables
        assertEq(address(pair1155.nft()), address(test1155));
        assertEq(address(pair1155.bondingCurve()), address(bondingCurve));
        assertEq(uint256(pair1155.poolType()), uint256(LSSVMPair.PoolType.TRADE));
        assertEq(pair1155.delta(), delta);
        assertEq(pair1155.spotPrice(), spotPrice);
        assertEq(pair1155.owner(), address(this));
        assertEq(pair1155.fee(), 0);
        assertEq(pair1155.getAssetRecipient(), address(pair1155));
        assertEq(getBalance(address(pair1155)), tokenAmount);

        // verify NFT ownership
        assertEq(test1155.balanceOf(address(pair1155), startingId), numItems);
    }

    function test_modifyPairParamsERC721() public {
        // changing spot works as expected
        pair.changeSpotPrice(2 ether);
        assertEq(pair.spotPrice(), 2 ether);

        // changing delta works as expected
        pair.changeDelta(2.2 ether);
        assertEq(pair.delta(), 2.2 ether);

        // // changing fee works as expected
        pair.changeFee(0.2 ether);
        assertEq(pair.fee(), 0.2 ether);
    }

    function test_modifyPairParamsERC1155() public {
        // changing spot works as expected
        pair1155.changeSpotPrice(2 ether);
        assertEq(pair1155.spotPrice(), 2 ether);

        // changing delta works as expected
        pair1155.changeDelta(2.2 ether);
        assertEq(pair1155.delta(), 2.2 ether);

        // // changing fee works as expected
        pair1155.changeFee(0.2 ether);
        assertEq(pair1155.fee(), 0.2 ether);
    }

    function test_multicallModifyPairParamsERC721() public {
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(pair.changeSpotPrice, (1 ether));
        calls[1] = abi.encodeCall(pair.changeDelta, (2 ether));
        calls[2] = abi.encodeCall(pair.changeFee, (0.3 ether));
        pair.multicall(calls, true);
        assertEq(pair.spotPrice(), 1 ether);
        assertEq(pair.delta(), 2 ether);
        assertEq(pair.fee(), 0.3 ether);
    }

    function test_multicallModifyPairParamsERC1155() public {
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(pair1155.changeSpotPrice, (1 ether));
        calls[1] = abi.encodeCall(pair1155.changeDelta, (2 ether));
        calls[2] = abi.encodeCall(pair1155.changeFee, (0.3 ether));
        pair1155.multicall(calls, true);
        assertEq(pair1155.spotPrice(), 1 ether);
        assertEq(pair1155.delta(), 2 ether);
        assertEq(pair1155.fee(), 0.3 ether);
    }

    function test_multicallChangeOwnershipERC721() public {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(pair.transferOwnership, (address(69), ""));
        calls[1] = abi.encodeCall(pair.changeDelta, (2 ether));
        vm.expectRevert(LSSVMPair.LSSVMPair__FunctionNotAllowed.selector);
        pair.multicall(calls, true);

        MockOwnershipTransferReceiver receiver = new MockOwnershipTransferReceiver();
        calls[0] = abi.encodeCall(pair.transferOwnership, (address(receiver), ""));
        vm.expectRevert(LSSVMPair.LSSVMPair__FunctionNotAllowed.selector);
        pair.multicall(calls, true);
    }

    function test_multicallChangeOwnershipERC1155() public {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(pair1155.transferOwnership, (address(69), ""));
        calls[1] = abi.encodeCall(pair1155.changeDelta, (2 ether));
        vm.expectRevert(LSSVMPair.LSSVMPair__FunctionNotAllowed.selector);
        pair1155.multicall(calls, true);

        MockOwnershipTransferReceiver receiver = new MockOwnershipTransferReceiver();
        calls[0] = abi.encodeCall(pair1155.transferOwnership, (address(receiver), ""));
        vm.expectRevert(LSSVMPair.LSSVMPair__FunctionNotAllowed.selector);
        pair1155.multicall(calls, true);
    }

    function test_withdraw() public {
        withdrawTokens(pair);
        assertEq(getBalance(address(pair)), 0);
    }

    function testFail_withdraw() public {
        pair.transferOwnership(address(1000), "");
        withdrawTokens(pair);
    }

    function test_withdraw1155() public {
        test1155.mint(address(pair), 1, 2);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2;
        pair.withdrawERC1155(IERC1155(address(test1155)), ids, amounts);
        assertEq(IERC1155(address(test1155)).balanceOf(address(pair), 1), 0);
        assertEq(IERC1155(address(test1155)).balanceOf(address(this), 1), 2);
    }

    function test_withdraw721() public {
        IERC721Mintable(address(test721)).mint(address(pair1155), 0);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        pair1155.withdrawERC721(IERC721(address(test721)), ids);
        assertEq(test721.ownerOf(0), address(this));
    }

    function test_depositERC1155(uint256 id, uint256 amount) public {
        id = bound(id, 1, type(uint256).max);

        test1155.mint(address(this), id, amount);
        test1155.setApprovalForAll(address(factory), true);
        factory.depositERC1155(test1155, id, address(pair1155), amount);
        assertEq(test1155.balanceOf(address(pair1155), id), amount, "didn't deposit ERC1155 NFTs");
    }

    function test_royaltyCannotExceedMax_ERC721() public {
        // increase royalty to large value
        uint96 bps = 9999;
        Test2981 test2981 = new Test2981(ROYALTY_RECEIVER, bps);
        RoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(test721), address(test2981));

        // set reasonable delta and spot price
        (uint128 delta_, uint128 spotPrice_) = getReasonableDeltaAndSpotPrice();
        pair.changeDelta(delta_);
        pair.changeSpotPrice(spotPrice_);

        // fetch buy info
        (,,, uint256 inputAmount,,) = bondingCurve.getBuyInfo(spotPrice_, delta_, 1, 0, protocolFeeMultiplier);

        // buy specific NFT
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        vm.expectRevert(LSSVMPair.LSSVMPair__RoyaltyTooLarge.selector);
        pair.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            nftIds, inputAmount, address(this), false, address(0)
        );
    }

    function test_royaltyCannotExceedMax_ERC1155() public {
        // increase royalty to large value
        uint96 bps = 9999;
        Test2981 test2981 = new Test2981(ROYALTY_RECEIVER, bps);
        RoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(test1155), address(test2981));

        // set reasonable delta and spot price
        (uint128 delta_, uint128 spotPrice_) = getReasonableDeltaAndSpotPrice();
        pair1155.changeDelta(delta_);
        pair1155.changeSpotPrice(spotPrice_);

        // fetch buy info
        (,,, uint256 inputAmount,,) = bondingCurve.getBuyInfo(spotPrice_, delta_, 1, 0, protocolFeeMultiplier);

        // buy specific NFT
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        vm.expectRevert(LSSVMPair.LSSVMPair__RoyaltyTooLarge.selector);
        pair1155.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            nftIds, inputAmount, address(this), false, address(0)
        );
    }

    function test_calculateRoyaltiesInvalidSettings() public {
        Test2981 test2981 = new Test2981(ROYALTY_RECEIVER, 100);
        RoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(test721), address(test2981));

        MockSettings mockSettings = new MockSettings();
        factory.toggleSettingsForCollection(address(mockSettings), address(test721), true);
        factory.enableSettingsForPair(address(mockSettings), address(pair));

        // Make sure that invalid settings don't cause a revert
        (address payable[] memory royaltyRecipients,, uint256 royaltyTotal) = pair.calculateRoyaltiesView(1, 1 ether);

        assertEq(royaltyTotal, 0.01 ether);
        assertEq(royaltyRecipients[0], ROYALTY_RECEIVER);
    }

    function test_brokenRegistryDoesNotBreakSwaps_ERC721() public {
        // setup contracts using broken registry
        royaltyEngine = new RoyaltyEngine(address(0x69));
        factory = setupFactory(royaltyEngine, feeRecipient, protocolFeeMultiplier);
        factory.setBondingCurveAllowed(bondingCurve, true);
        test721.setApprovalForAll(address(factory), true);
        (uint128 delta_, uint128 spotPrice_) = getReasonableDeltaAndSpotPrice();
        IERC721Mintable(address(test721)).mint(address(this), numItems + 1);
        uint256[] memory idList_ = new uint256[](1);
        idList_[0] = numItems + 1;
        pair = this.setupPairERC721{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            delta_,
            0,
            spotPrice_,
            idList_,
            tokenAmount,
            address(0)
        );

        // fetch buy info
        (,,, uint256 inputAmount,,) = bondingCurve.getBuyInfo(spotPrice_, delta_, 1, 0, protocolFeeMultiplier);

        // buy specific NFT
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = numItems + 1;
        pair.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            nftIds, inputAmount, address(this), false, address(0)
        );
    }

    function test_brokenRegistryDoesNotBreakSwaps_ERC1155() public {
        // setup contracts using broken registry
        royaltyEngine = new RoyaltyEngine(address(0x69));
        factory = setupFactory(royaltyEngine, feeRecipient, protocolFeeMultiplier);
        factory.setBondingCurveAllowed(bondingCurve, true);
        test1155.setApprovalForAll(address(factory), true);
        (uint128 delta_, uint128 spotPrice_) = getReasonableDeltaAndSpotPrice();
        test1155.mint(address(this), startingId, numItems);
        pair1155 = this.setupPairERC1155{value: modifyInputAmount(tokenAmount)}(
            CreateERC1155PairParams(
                factory,
                test1155,
                bondingCurve,
                payable(address(0)),
                LSSVMPair.PoolType.TRADE,
                delta_,
                0,
                spotPrice_,
                startingId,
                numItems,
                tokenAmount,
                address(0),
                address(0)
            )
        );

        // fetch buy info
        (,,, uint256 inputAmount,,) = bondingCurve.getBuyInfo(spotPrice_, delta_, 1, 0, protocolFeeMultiplier);

        // buy specific NFT
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        pair1155.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            nftIds, inputAmount, address(this), false, address(0)
        );
    }

    function test_pairIdSet() public {
        // Check ID list
        uint256[] memory storedIds = LSSVMPairERC721(address(pair)).getIds(0, idList.length);
        assertEq(storedIds.length, idList.length);
        for (uint256 i = 1; i <= numItems; i++) {
            LSSVMPairERC721(address(pair)).hasId(i);
        }

        uint256[] memory storedIdsAll = LSSVMPairERC721(address(pair)).getAllIds();
        for (uint256 i = 1; i <= numItems; i++) {
            LSSVMPairERC721(address(pair)).hasId(i);
        }
    }

    function test_depositModifiesPairIdSet() public {
        // Call deposit NFTs from the pair factory
        IERC721Mintable(address(test721)).mint(address(this), 69);
        uint256[] memory id = new uint256[](1);
        id[0] = 69;
        factory.depositNFTs(IERC721(address(test721)), id, address(pair));
        assertEq(LSSVMPairERC721(address(pair)).numIdsHeld(), numItems + 1);
        assertEq(LSSVMPairERC721(address(pair)).hasId(69), true);
    }

    /**
     * Test failure conditions
     */

    function testFail_rescueTokensNotOwnerERC721() public {
        pair.transferOwnership(address(1000), "");
        pair.withdrawERC721(test721, idList);
        pair.withdrawERC20(testERC20, 1 ether);
    }

    function testFail_rescueTokensNotOwnerERC1155() public {
        pair1155.transferOwnership(address(1000), "");
        pair1155.withdrawERC721(test721, idList);
        pair1155.withdrawERC20(testERC20, 1 ether);
    }

    function testFail_changeFeeAboveMaxERC721() public {
        pair.changeFee(100 ether);
    }

    function testFail_changeFeeAboveMax1155() public {
        pair1155.changeFee(100 ether);
    }

    function testFail_changeSpotNotOwnerERC721() public {
        pair.transferOwnership(address(1000), "");
        pair.changeSpotPrice(2 ether);
    }

    function testFail_changeSpotNotOwnerERC1155() public {
        pair1155.transferOwnership(address(1000), "");
        pair1155.changeSpotPrice(2 ether);
    }

    function testFail_changeDeltaNotOwnerERC721() public {
        pair.transferOwnership(address(1000), "");
        pair.changeDelta(2.2 ether);
    }

    function testFail_changeDeltaNotOwnerERC1155() public {
        pair1155.transferOwnership(address(1000), "");
        pair1155.changeDelta(2.2 ether);
    }

    function testFail_changeFeeNotOwnerERC721() public {
        pair.transferOwnership(address(1000), "");
        pair.changeFee(0.2 ether);
    }

    function testFail_changeFeeNotOwnerERC1155() public {
        pair1155.transferOwnership(address(1000), "");
        pair1155.changeFee(0.2 ether);
    }

    function testFail_reInitPoolERC721() public {
        pair.initialize(address(0), payable(address(0)), 0, 0, 0, address(0), address(0));
    }

    function testFail_reInitPoolERC1155() public {
        pair.initialize(address(0), payable(address(0)), 0, 0, 0, address(0), address(0));
    }

    function testFail_swapForNFTNotInPoolERC721() public {
        (, uint128 newSpotPrice,, uint256 inputAmount,,) =
            bondingCurve.getBuyInfo(spotPrice, delta, numItems + 1, 0, protocolFeeMultiplier);

        // buy specific NFT not in pool
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 69;
        pair.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            nftIds, inputAmount, address(this), false, address(0)
        );
        spotPrice = uint56(newSpotPrice);
    }

    function testFail_swapForNFTNotInPoolERC1155() public {
        (, uint128 newSpotPrice,, uint256 inputAmount,,) =
            bondingCurve.getBuyInfo(spotPrice, delta, numItems + 1, 0, protocolFeeMultiplier);

        // buy specific NFT not in pool
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 69420;
        pair1155.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            nftIds, inputAmount, address(this), false, address(0)
        );
        spotPrice = uint56(newSpotPrice);
    }

    /**
     * Test Admin functions
     */

    function test_changeDefaultProtocolFeeRecipient() public {
        factory.changeDefaultProtocolFeeRecipient(payable(address(69)));
        assertEq(factory.defaultProtocolFeeRecipient(), address(69));

        vm.prank(address(1));
        vm.expectRevert();
        factory.changeDefaultProtocolFeeRecipient(payable(address(69)));
    }

    function test_addProtocolFeeReferral() public {
        factory.addProtocolFeeRecipientReferral(address(101), payable(address(102)));
        assertEq(factory.protocolFeeRecipientReferral(address(101)), address(102));

        vm.prank(address(1));
        vm.expectRevert();
        factory.addProtocolFeeRecipientReferral(address(101), payable(address(102)));

        // Check getProtocolFeeRecipient()
        assertEq(factory.getProtocolFeeRecipient(address(101)), address(102));
        assertEq(factory.getProtocolFeeRecipient(address(0)), address(factory));
    }

    function test_withdrawFees() public {
        uint256 totalProtocolFee;
        uint256 factoryEndBalance;
        uint256 factoryStartBalance = getBalance(address(69));

        test721.setApprovalForAll(address(pair), true);

        // buy all NFTs
        {
            (, uint128 newSpotPrice,, uint256 inputAmount, /* tradeFee */, uint256 protocolFee) =
                bondingCurve.getBuyInfo(spotPrice, delta, numItems, 0, protocolFeeMultiplier);
            totalProtocolFee += protocolFee;

            // buy NFTs
            pair.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
                idList, inputAmount, address(this), false, address(0)
            );
            spotPrice = uint56(newSpotPrice);
        }

        this.withdrawProtocolFees(factory);

        factoryEndBalance = getBalance(address(69));
        assertEq(factoryEndBalance, factoryStartBalance + totalProtocolFee);
    }

    function test_changeFeeMultiplier() public {
        factory.changeProtocolFeeMultiplier(5e15);
        assertEq(factory.protocolFeeMultiplier(), 5e15);
    }
}
