// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";
import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Test721} from "../../mocks/Test721.sol";
import {MaliciousRouter} from "../../mocks/MaliciousRouter.sol";

import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {IERC1155Mintable} from "../interfaces/IERC1155Mintable.sol";
import {IPropertyChecker} from "../../property-checking/IPropertyChecker.sol";
import {RangePropertyChecker} from "../../property-checking/RangePropertyChecker.sol";
import {MerklePropertyChecker} from "../../property-checking/MerklePropertyChecker.sol";
import {PropertyCheckerFactory} from "../../property-checking/PropertyCheckerFactory.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {ILSSVMPair} from "../../ILSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {LSSVMPairERC20} from "../../LSSVMPairERC20.sol";
import {VeryFastRouter} from "../../VeryFastRouter.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";

abstract contract MaliciousRouterFailsSwap is Test, ERC721Holder, ERC1155Holder, ConfigurableWithRoyalties {
    ICurve bondingCurve;
    RoyaltyEngine royaltyEngine;
    LSSVMPairFactory pairFactory;
    PropertyCheckerFactory propertyCheckerFactory;
    MaliciousRouter router;
    ERC2981 test2981;

    uint128 delta;
    uint128 spotPrice;

    address constant ROUTER_CALLER = address(1);
    address constant TOKEN_RECIPIENT = address(420);
    address constant NFT_RECIPIENT = address(0x69);

    address constant PAIR_RECIPIENT = address(1111111111);

    uint256 constant START_INDEX = 0;
    uint256 constant END_INDEX = 10;
    uint256 constant NUM_ITEMS_TO_SWAP = 5;
    uint256 constant SHIFT_AMOUNT = 1;
    uint256 constant SLIPPAGE = 1e8; // small % slippage allowed for partial fill quotes (due to numerical instability)

    enum SellSwap {
        IGNORE_PROPERTY_CHECK,
        IGNORE_TRANSFER_ERC721,
        IGNORE_TRANSFER_ERC721_NO_PROPERTY_CHECK,
        IGNORE_TRANSFER_ERC1155
    }

    enum BuySwap {
        IGNORE_TRANSFER_ERC20,
        TRANSFER_LESS_ERC20,
        TRANFER_ERC20_NO_ROYALTY
    }

    function setUp() public {
        bondingCurve = setupCurve();
        royaltyEngine = setupRoyaltyEngine();
        pairFactory = setupFactory(royaltyEngine, payable(address(0)));
        pairFactory.setBondingCurveAllowed(bondingCurve, true);
        test2981 = setup2981();

        MerklePropertyChecker checker1 = new MerklePropertyChecker();
        RangePropertyChecker checker2 = new RangePropertyChecker();
        propertyCheckerFactory = new PropertyCheckerFactory(checker1, checker2);

        // Deploy malicious router
        router = new MaliciousRouter(pairFactory);

        pairFactory.setRouterAllowed(LSSVMRouter(payable(address(router))), true);

        (delta, spotPrice) = getReasonableDeltaAndSpotPrice();

        // Give the router caller a large amount of ETH
        vm.deal(ROUTER_CALLER, 1e18 ether);
    }

    function _getArray(uint256 start, uint256 end) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](end - start + 1);
        for (uint256 i = 0; i < ids.length; i++) {
            ids[i] = start + i;
        }
    }

    function _setUpERC721(address nftRecipient, address factoryCaller, address routerCaller)
        internal
        returns (IERC721Mintable nft)
    {
        nft = IERC721Mintable(address(new Test721()));
        IRoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(nft), address(test2981));

        for (uint256 i = START_INDEX; i <= END_INDEX; i++) {
            nft.mint(nftRecipient, i);
        }
        vm.prank(factoryCaller);
        nft.setApprovalForAll(address(pairFactory), true);
        vm.prank(routerCaller);
        nft.setApprovalForAll(address(router), true);
    }

    function setUpPairERC721ForSale(
        LSSVMPair.PoolType poolType,
        address nftRecipient,
        uint256 depositAmount,
        address _propertyChecker,
        uint256[] memory nftIdsToDeposit
    ) public returns (LSSVMPair pair) {
        pair = this.setupPairWithPropertyCheckerERC721{value: modifyInputAmount(depositAmount)}(
            PairCreationParamsWithPropertyCheckerERC721({
                factory: pairFactory,
                nft: IERC721(address(_setUpERC721(nftRecipient, address(this), ROUTER_CALLER))),
                bondingCurve: bondingCurve,
                assetRecipient: payable(address(0)),
                poolType: poolType,
                delta: delta,
                fee: 0,
                spotPrice: spotPrice,
                _idList: nftIdsToDeposit,
                initialTokenBalance: depositAmount,
                routerAddress: address(router),
                propertyChecker: _propertyChecker
            })
        );
    }

    function setUpPairERC721ForSale(
        LSSVMPair.PoolType poolType,
        IERC721 nft,
        address,
        uint256 depositAmount,
        address _propertyChecker,
        uint256[] memory nftIdsToDeposit
    ) public returns (LSSVMPair pair) {
        pair = this.setupPairWithPropertyCheckerERC721{value: modifyInputAmount(depositAmount)}(
            PairCreationParamsWithPropertyCheckerERC721({
                factory: pairFactory,
                nft: nft,
                bondingCurve: bondingCurve,
                assetRecipient: payable(address(0)),
                poolType: poolType,
                delta: delta,
                fee: 0,
                spotPrice: spotPrice,
                _idList: nftIdsToDeposit,
                initialTokenBalance: depositAmount,
                routerAddress: address(router),
                propertyChecker: _propertyChecker
            })
        );
    }

    function _getSellOrderIgnorePropertyCheck()
        public
        returns (MaliciousRouter.SellOrderWithPartialFill memory sellOrder, bytes4 revertMsg)
    {
        // Only accept IDs from START_INDEX to NUM_ITEMS_TO_SWAP
        address propertyCheckerAddress =
            address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, NUM_ITEMS_TO_SWAP));

        // Set up pair with no tokens
        uint256[] memory emptyList = new uint256[](0);
        LSSVMPair pair =
            setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, ROUTER_CALLER, 0, propertyCheckerAddress, emptyList);

        // Get array of all NFT IDs we want to sell
        uint256[] memory nftIds = _getArray(START_INDEX, NUM_ITEMS_TO_SWAP);

        // Get the amount needed to put in the pair to support selling everything (i.e. more than we need)
        // Get new spot price and delta as if we had sold END_INDEX number of NFTs
        (,,, uint256 outputAmount,, uint256 protocolFee) = pair.bondingCurve().getSellInfo(
            pair.spotPrice(), pair.delta(), nftIds.length, pair.fee(), pair.factory().protocolFeeMultiplier()
        );

        // Send that many tokens to the pair
        sendTokens(pair, outputAmount + protocolFee);

        // Get modified nft ids
        uint256[] memory modifiedNftIds = _getArray(START_INDEX + SHIFT_AMOUNT, NUM_ITEMS_TO_SWAP + SHIFT_AMOUNT);

        // Set it in the malicious router for ids to transfer
        router.setIdsToTransfer(modifiedNftIds);

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Construct the sell order
        // Calculate the max amount we can receive
        (,,, uint256 expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, nftIds.length);
        sellOrder = MaliciousRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: true,
            nftIds: nftIds,
            doPropertyCheck: true,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice() + 1, // Trigger partial fill calculation
            minExpectedOutput: expectedOutput,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(
                pair, nftIds.length, SLIPPAGE, START_INDEX
                )
        });

        revertMsg = LSSVMPair.LSSVMPair__NftNotTransferred.selector;
    }

    function _getSellOrderIgnoreNFTTransfer(address propertyCheckerAddress)
        public
        returns (MaliciousRouter.SellOrderWithPartialFill memory sellOrder, bytes4 revertMsg)
    {
        // Set up pair with no tokens
        uint256[] memory emptyList = new uint256[](0);
        LSSVMPair pair =
            setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, ROUTER_CALLER, 0, propertyCheckerAddress, emptyList);

        // Get array of all NFT IDs we want to sell
        uint256[] memory nftIds = _getArray(START_INDEX, NUM_ITEMS_TO_SWAP);

        // Get the amount needed to put in the pair to support selling everything (i.e. more than we need)
        // Get new spot price and delta as if we had sold END_INDEX number of NFTs
        (,,, uint256 outputAmount,, uint256 protocolFee) = pair.bondingCurve().getSellInfo(
            pair.spotPrice(), pair.delta(), nftIds.length, pair.fee(), pair.factory().protocolFeeMultiplier()
        );

        // Send that many tokens to the pair
        sendTokens(pair, outputAmount + protocolFee);

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Disable transfers
        router.setDisabledReceivers(address(pair), true);

        // Construct the sell order
        // Calculate the max amount we can receive
        (,,, uint256 expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, nftIds.length);
        sellOrder = MaliciousRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: true,
            nftIds: nftIds,
            doPropertyCheck: (propertyCheckerAddress != address(0)),
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice() + 1, // Trigger partial fill calculation
            minExpectedOutput: expectedOutput,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(
                pair, nftIds.length, SLIPPAGE, START_INDEX
                )
        });

        revertMsg = LSSVMPair.LSSVMPair__NftNotTransferred.selector;
    }

    function _getSellOrderIgnoreNFTTransfer1155()
        public
        returns (MaliciousRouter.SellOrderWithPartialFill memory sellOrder, bytes4 revertMsg)
    {
        IERC1155Mintable nft = setup1155();
        nft.mint(address(this), 1, 1);
        nft.setApprovalForAll(address(pairFactory), true);
        LSSVMPair pair = this.setupPairERC1155{value: modifyInputAmount(10 ether)}(
            CreateERC1155PairParams({
                factory: pairFactory,
                nft: nft,
                bondingCurve: bondingCurve,
                assetRecipient: payable(address(0)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: delta,
                fee: 0, // fee
                spotPrice: spotPrice,
                nftId: 1,
                initialNFTBalance: 0,
                initialTokenBalance: 10 ether,
                routerAddress: address(router)
            })
        );
        uint256[] memory nftInfo = new uint256[](1);
        nftInfo[0] = 1;
        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Disable pulling to the
        router.setDisabledReceivers(address(pair), true);

        sellOrder = MaliciousRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: false,
            nftIds: nftInfo,
            doPropertyCheck: false,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice() + 1, // Trigger partial fill calculation
            minExpectedOutput: 0,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(pair, 1, SLIPPAGE, START_INDEX)
        });
        revertMsg = LSSVMPair.LSSVMPair__NftNotTransferred.selector;
    }

    function _getBuyOrderIgnoreERC20Transfer()
        public
        returns (MaliciousRouter.BuyOrderWithPartialFill memory buyOrder, bytes4 revertMsg)
    {
        // Set up pair with empty property checker as PAIR_CREATOR
        uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);
        LSSVMPair pair = setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, address(this), 0, address(0), nftIds);
        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, nftIds.length);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, nftIds.length, SLIPPAGE, nftIds[0]);

        // Assert that we are sending as many tokens as needed in the case where we fill everything
        assertApproxEqRel(inputAmount, partialFillAmounts[partialFillAmounts.length - 1], 1e9, "Difference too large");

        // Disable transfers
        router.resetIndexToGet();
        router.setDisabledReceivers(ROYALTY_RECEIVER, false);
        router.setDisabledReceivers(address(pair), true);

        buyOrder = MaliciousRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftIds,
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice(),
            isERC721: true,
            maxCostPerNumNFTs: partialFillAmounts
        });

        // Only set revert message if ERC20 pair
        if (getTokenAddress() != address(0)) {
            revertMsg = LSSVMPairERC20.LSSVMPairERC20__AssetRecipientNotPaid.selector;
        }
    }

    function _getBuyOrderIgnoreERC20RoyaltyPayment()
        public
        returns (MaliciousRouter.BuyOrderWithPartialFill memory buyOrder, bytes4 revertMsg)
    {
        // Set up pair with empty property checker as PAIR_CREATOR
        uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);
        LSSVMPair pair = setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, address(this), 0, address(0), nftIds);
        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, nftIds.length);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, nftIds.length, SLIPPAGE, nftIds[0]);

        // Assert that we are sending as many tokens as needed in the case where we fill everything
        assertApproxEqRel(inputAmount, partialFillAmounts[partialFillAmounts.length - 1], 1e9, "Difference too large");

        // Disable transfers to royalty receiver
        router.resetIndexToGet();
        router.setDisabledReceivers(address(pair), false);
        router.setDisabledReceivers(ROYALTY_RECEIVER, true);

        buyOrder = MaliciousRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftIds,
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice(),
            isERC721: true,
            maxCostPerNumNFTs: partialFillAmounts
        });

        // Only set revert message if ERC20 pair
        if (getTokenAddress() != address(0)) {
            revertMsg = LSSVMPairERC20.LSSVMPairERC20__RoyaltyNotPaid.selector;
        }
    }

    function _getBuyOrderSendLessERC20()
        public
        returns (MaliciousRouter.BuyOrderWithPartialFill memory buyOrder, bytes4 revertMsg)
    {
        // Set up pair with empty property checker as PAIR_CREATOR
        uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);
        LSSVMPair pair = setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, address(this), 0, address(0), nftIds);
        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, nftIds.length);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, nftIds.length, SLIPPAGE, nftIds[0]);

        // Assert that we are sending as many tokens as needed in the case where we fill everything
        assertApproxEqRel(inputAmount, partialFillAmounts[partialFillAmounts.length - 1], 1e9, "Difference too large");

        // Set transfer amount to be very low
        router.setIndex(1);

        buyOrder = MaliciousRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftIds,
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice(),
            isERC721: true,
            maxCostPerNumNFTs: partialFillAmounts
        });

        // Only set revert message if ERC20 pair
        if (getTokenAddress() != address(0)) {
            revertMsg = LSSVMPairERC20.LSSVMPairERC20__AssetRecipientNotPaid.selector;
        }
    }

    function _getSellOrder(SellSwap swapType)
        public
        returns (MaliciousRouter.SellOrderWithPartialFill memory sellOrder, bytes4 revertMsg)
    {
        if (swapType == SellSwap.IGNORE_PROPERTY_CHECK) {
            return _getSellOrderIgnorePropertyCheck();
        } else if (swapType == SellSwap.IGNORE_TRANSFER_ERC721) {
            // Only accept IDs from START_INDEX to NUM_ITEMS_TO_SWAP
            address propertyCheckerAddress =
                address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, NUM_ITEMS_TO_SWAP));
            return _getSellOrderIgnoreNFTTransfer(propertyCheckerAddress);
        } else if (swapType == SellSwap.IGNORE_TRANSFER_ERC721_NO_PROPERTY_CHECK) {
            return _getSellOrderIgnoreNFTTransfer(address(0));
        } else if (swapType == SellSwap.IGNORE_TRANSFER_ERC1155) {
            return _getSellOrderIgnoreNFTTransfer1155();
        }
    }

    function _getBuyOrder(BuySwap swapType)
        public
        returns (MaliciousRouter.BuyOrderWithPartialFill memory sellOrder, bytes4 revertMsg)
    {
        if (swapType == BuySwap.IGNORE_TRANSFER_ERC20) {
            return _getBuyOrderIgnoreERC20Transfer();
        } else if (swapType == BuySwap.TRANSFER_LESS_ERC20) {
            return _getBuyOrderSendLessERC20();
        } else if (swapType == BuySwap.TRANFER_ERC20_NO_ROYALTY) {
            return _getBuyOrderIgnoreERC20RoyaltyPayment();
        }
    }

    function test_maliciousRouterSwap() public {
        for (uint256 i = 0; i < uint256(type(SellSwap).max) + 1; i++) {
            (MaliciousRouter.SellOrderWithPartialFill memory sellOrder, bytes4 revertMsg) = _getSellOrder(SellSwap(i));

            MaliciousRouter.SellOrderWithPartialFill[] memory sellOrders =
                new MaliciousRouter.SellOrderWithPartialFill[](1);
            sellOrders[0] = sellOrder;

            MaliciousRouter.BuyOrderWithPartialFill[] memory buyOrders =
                new MaliciousRouter.BuyOrderWithPartialFill[](0);

            // Set up the actual VFR swap
            MaliciousRouter.Order memory swapOrder = MaliciousRouter.Order({
                buyOrders: buyOrders,
                sellOrders: sellOrders,
                tokenRecipient: payable(address(TOKEN_RECIPIENT)),
                nftRecipient: NFT_RECIPIENT,
                recycleETH: false
            });

            // Prank as the router caller and do the swap
            vm.startPrank(ROUTER_CALLER);

            // Set up approval for token if it is a token pair (for router caller)
            address tokenAddress = getTokenAddress();
            if (tokenAddress != address(0)) {
                ERC20(tokenAddress).approve(address(router), 1e18 ether);
                IMintable(tokenAddress).mint(ROUTER_CALLER, 1e18 ether);
            }

            // Perform the swap
            vm.expectRevert(revertMsg);
            router.swap{value: 0}(swapOrder);
            vm.stopPrank();
        }
        for (uint256 i = 0; i < uint256(type(BuySwap).max) + 1; i++) {
            (MaliciousRouter.BuyOrderWithPartialFill memory buyOrder, bytes4 revertMsg) = _getBuyOrder(BuySwap(i));

            MaliciousRouter.SellOrderWithPartialFill[] memory sellOrders =
                new MaliciousRouter.SellOrderWithPartialFill[](0);

            MaliciousRouter.BuyOrderWithPartialFill[] memory buyOrders =
                new MaliciousRouter.BuyOrderWithPartialFill[](1);
            buyOrders[0] = buyOrder;

            // Set up the actual VFR swap
            MaliciousRouter.Order memory swapOrder = MaliciousRouter.Order({
                buyOrders: buyOrders,
                sellOrders: sellOrders,
                tokenRecipient: payable(address(TOKEN_RECIPIENT)),
                nftRecipient: NFT_RECIPIENT,
                recycleETH: false
            });

            // Prank as the router caller and do the swap
            vm.startPrank(ROUTER_CALLER);

            // Set up approval for token if it is a token pair (for router caller)
            address tokenAddress = getTokenAddress();
            if (tokenAddress != address(0)) {
                ERC20(tokenAddress).approve(address(router), 1e18 ether);
                IMintable(tokenAddress).mint(ROUTER_CALLER, 1e18 ether);

                // Perform the swap only for ERC20 pairs
                vm.expectRevert(revertMsg);
                router.swap{value: 0}(swapOrder);
            }

            vm.stopPrank();
        }
    }

    function test_reenterSellSwap() public {
        IERC721 nft = _setUpERC721(ROUTER_CALLER, ROUTER_CALLER, ROUTER_CALLER);

        // Create 2 pairs willing to buy at the same price
        LSSVMPair pair1 =
            setUpPairERC721ForSale(LSSVMPair.PoolType.TOKEN, nft, address(this), 0, address(0), new uint256[](0));
        LSSVMPair pair2 =
            setUpPairERC721ForSale(LSSVMPair.PoolType.TOKEN, nft, address(this), 0, address(0), new uint256[](0));

        // Get the amount needed to put in the pair to support selling 1 NFT
        (,,, uint256 outputAmount,, uint256 protocolFee) = pair1.bondingCurve().getSellInfo(
            pair1.spotPrice(), pair1.delta(), 1, pair1.fee(), pair1.factory().protocolFeeMultiplier()
        );

        // Send that many tokens to both pairs
        sendTokens(pair1, outputAmount + protocolFee);
        sendTokens(pair2, outputAmount + protocolFee);

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Set both to have the same asset recipient
        pair1.changeAssetRecipient(payable(PAIR_RECIPIENT));
        pair2.changeAssetRecipient(payable(PAIR_RECIPIENT));

        // Set the malicious router configs
        router.setReenter(true);
        router.setPair721ToTriggerCallback(pair1);
        router.setPair721ToEnter(pair2);

        MaliciousRouter.SellOrderWithPartialFill memory sellOrder = MaliciousRouter.SellOrderWithPartialFill({
            pair: pair1,
            isETHSell: isETHSell,
            isERC721: true,
            nftIds: new uint256[](1), // Sell ID 0
            doPropertyCheck: false,
            propertyCheckParams: "",
            expectedSpotPrice: pair1.spotPrice(),
            minExpectedOutput: 0,
            minExpectedOutputPerNumNFTs: new uint256[](1)
        });

        MaliciousRouter.SellOrderWithPartialFill[] memory sellOrders = new MaliciousRouter.SellOrderWithPartialFill[](1);
        sellOrders[0] = sellOrder;

        MaliciousRouter.BuyOrderWithPartialFill[] memory buyOrders = new MaliciousRouter.BuyOrderWithPartialFill[](0);

        // Set up the actual VFR swap
        MaliciousRouter.Order memory swapOrder = MaliciousRouter.Order({
            buyOrders: buyOrders,
            sellOrders: sellOrders,
            tokenRecipient: payable(address(TOKEN_RECIPIENT)),
            nftRecipient: NFT_RECIPIENT,
            recycleETH: false
        });

        // Prank as the router caller and do the swap
        vm.startPrank(ROUTER_CALLER);

        // Expect revert on malicious call
        vm.expectRevert(LSSVMPairFactory.LSSVMPairFactory__ReentrantCall.selector);
        router.swap{value: 0}(swapOrder);
    }

    function test_reenterBuySwap() public {
        IERC721 nft = _setUpERC721(address(this), address(this), ROUTER_CALLER);

        uint256[] memory id1 = new uint256[](1);
        uint256[] memory id2 = new uint256[](1);
        id1[0] = 0;
        id2[0] = 1;

        // Create 2 pairs willing to buy at the same price
        LSSVMPair pair1 = setUpPairERC721ForSale(LSSVMPair.PoolType.NFT, nft, address(this), 0, address(0), id1);
        LSSVMPair pair2 = setUpPairERC721ForSale(LSSVMPair.PoolType.NFT, nft, address(this), 0, address(0), id2);

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        // Only do call for ERC20 pairs
        if (tokenAddress != address(0)) {
            isETHSell = false;
        } else {
            return;
        }

        // Set both to have the same asset recipient
        pair1.changeAssetRecipient(payable(PAIR_RECIPIENT));
        pair2.changeAssetRecipient(payable(PAIR_RECIPIENT));

        // Set the malicious router configs
        router.setReenter(true);
        router.setPair721ToTriggerCallback(pair1);
        router.setPair721ToEnter(pair2);

        MaliciousRouter.SellOrderWithPartialFill[] memory sellOrders = new MaliciousRouter.SellOrderWithPartialFill[](0);

        MaliciousRouter.BuyOrderWithPartialFill[] memory buyOrders = new MaliciousRouter.BuyOrderWithPartialFill[](1);

        uint256[] memory maxCost = new uint256[](1);
        maxCost[0] = type(uint256).max;
        buyOrders[0] = MaliciousRouter.BuyOrderWithPartialFill({
            pair: pair1,
            nftIds: new uint256[](1),
            maxInputAmount: type(uint256).max,
            ethAmount: 0,
            expectedSpotPrice: pair1.spotPrice(),
            isERC721: true,
            maxCostPerNumNFTs: maxCost
        });

        // Set up the actual VFR swap
        MaliciousRouter.Order memory swapOrder = MaliciousRouter.Order({
            buyOrders: buyOrders,
            sellOrders: sellOrders,
            tokenRecipient: payable(address(TOKEN_RECIPIENT)),
            nftRecipient: NFT_RECIPIENT,
            recycleETH: false
        });

        // Prank as the router caller and do the swap
        vm.startPrank(ROUTER_CALLER);

        // Set approval
        ERC20(tokenAddress).approve(address(router), 1e18 ether);
        IMintable(tokenAddress).mint(ROUTER_CALLER, 1e18 ether);

        // Perform the swap
        vm.expectRevert(LSSVMPairFactory.LSSVMPairFactory__ReentrantCall.selector);
        router.swap{value: 0}(swapOrder);
    }

    function test_reenterBuySwapSamePair() public {
        IERC721 nft = _setUpERC721(address(this), address(this), ROUTER_CALLER);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;

        // Create pair
        LSSVMPair pair = setUpPairERC721ForSale(LSSVMPair.PoolType.NFT, nft, address(this), 0, address(0), ids);

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        // Only do call for ERC20 pairs
        if (tokenAddress != address(0)) {
            isETHSell = false;
        } else {
            return;
        }

        // Set the malicious router configs
        router.setReenter(true);
        router.setPair721ToTriggerCallback(pair);
        router.setPair721ToEnter(pair);

        MaliciousRouter.SellOrderWithPartialFill[] memory sellOrders = new MaliciousRouter.SellOrderWithPartialFill[](0);

        MaliciousRouter.BuyOrderWithPartialFill[] memory buyOrders = new MaliciousRouter.BuyOrderWithPartialFill[](1);

        uint256[] memory maxCost = new uint256[](1);
        maxCost[0] = type(uint256).max;
        buyOrders[0] = MaliciousRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: new uint256[](1),
            maxInputAmount: type(uint256).max,
            ethAmount: 0,
            expectedSpotPrice: pair.spotPrice(),
            isERC721: true,
            maxCostPerNumNFTs: maxCost
        });

        // Set up the actual VFR swap
        MaliciousRouter.Order memory swapOrder = MaliciousRouter.Order({
            buyOrders: buyOrders,
            sellOrders: sellOrders,
            tokenRecipient: payable(address(TOKEN_RECIPIENT)),
            nftRecipient: NFT_RECIPIENT,
            recycleETH: false
        });

        // Prank as the router caller and do the swap
        vm.startPrank(ROUTER_CALLER);

        // Set approval
        ERC20(tokenAddress).approve(address(router), 1e18 ether);
        IMintable(tokenAddress).mint(ROUTER_CALLER, 1e18 ether);

        // Perform the swap
        vm.expectRevert(LSSVMPairFactory.LSSVMPairFactory__ReentrantCall.selector);
        router.swap{value: 0}(swapOrder);
    }
}
