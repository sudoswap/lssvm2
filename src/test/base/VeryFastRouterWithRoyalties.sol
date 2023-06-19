// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";
import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";

import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Test721} from "../../mocks/Test721.sol";
import {Test1155} from "../../mocks/Test1155.sol";

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
import {VeryFastRouter} from "../../VeryFastRouter.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";

abstract contract VeryFastRouterWithRoyalties is Test, ERC721Holder, ERC1155Holder, ConfigurableWithRoyalties {
    ICurve bondingCurve;
    RoyaltyEngine royaltyEngine;
    LSSVMPairFactory pairFactory;
    PropertyCheckerFactory propertyCheckerFactory;
    VeryFastRouter router;
    ERC2981 test2981;

    address constant ROUTER_CALLER = address(1);
    address constant TOKEN_RECIPIENT = address(420);
    address constant NFT_RECIPIENT = address(0x69);

    uint256 constant START_INDEX = 0;
    uint256 constant NUM_BEFORE_PARTIAL_FILL = 2;
    uint256 constant PARTIAL_FILL_INDEX = 5;
    uint256 constant END_INDEX = 10;
    uint256 constant SLIPPAGE = 1e8; // small % slippage allowed for partial fill quotes (due to numerical instability)

    uint256 constant END_INDEX_RECYCLE = 0;
    uint256 constant ID_1155 = 0;

    uint128 delta;
    uint128 spotPrice;

    /**
     * Swap Order types
     */
    enum BuySwap {
        ITEM_PARTIAL_PRICE_FULL_721,
        ITEM_NONE_PRICE_FULL_721,
        ITEM_FULL_PRICE_PARTIAL_721,
        ITEM_FULL_PRICE_FULL_721,
        ITEM_PARTIAL_PRICE_PARTIAL_721,
        ITEM_FULL_PRICE_NONE_721,
        ITEM_FULL_PRICE_FULL_1155,
        ITEM_PARTIAL_PRICE_FULL_1155,
        ITEM_FULL_PRICE_PARTIAL_1155,
        ITEM_PARTIAL_PRICE_PARTIAL_1155,
        ITEM_NONE_PRICE_FULL_1155,
        ITEM_FULL_PRICE_NONE_1155
    }
    enum SellSwap {
        PRICE_FULL_BALANCE_PARTIAL_721,
        PRICE_PARTIAL_BALANCE_NONE_721,
        PRICE_PARTIAL_BALANCE_PARTIAL_721,
        PRICE_PARTIAL_BALANCE_FULL_721,
        PRICE_FULL_BALANCE_FULL_721,
        PRICE_NONE_BALANCE_FULL_721,
        PRICE_FULL_BALANCE_FULL_1155,
        PRICE_FULL_BALANCE_PARTIAL_1155,
        PRICE_PARTIAL_BALANCE_FULL_1155,
        PRICE_PARTIAL_BALANCE_PARTIAL_1155,
        PRICE_PARTIAL_BALANCE_NONE_1155,
        PRICE_NONE_BALANCE_FULL_1155
    }

    /**
     * The results of performing a swap
     */
    struct BuyResult {
        address nftRecipient;
        uint256 numItemsReceived;
        uint256[] idsReceived;
        LSSVMPair pair;
        bool isERC721;
    }

    struct SellResult {
        address nftRecipient;
        uint256 numItemsReceived;
        uint256[] idsReceived;
        LSSVMPair pair;
        bool isERC721;
        address tokenRecipient;
        uint256 tokenBalance;
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

        router = new VeryFastRouter(pairFactory);
        pairFactory.setRouterAllowed(LSSVMRouter(payable(address(router))), true);

        (delta, spotPrice) = getReasonableDeltaAndSpotPrice();

        // Give the router caller a large amount of ETH
        vm.deal(ROUTER_CALLER, 1e18 ether);
    }

    function _setUpERC721(address nftRecipient, address factoryCaller, address routerCaller)
        internal
        returns (IERC721Mintable nft)
    {
        nft = setup721();
        for (uint256 i = START_INDEX; i <= END_INDEX; i++) {
            nft.mint(nftRecipient, i);
        }
        // Set royalties
        IRoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(nft), address(test2981));
        vm.prank(factoryCaller);
        nft.setApprovalForAll(address(pairFactory), true);
        vm.prank(routerCaller);
        nft.setApprovalForAll(address(router), true);
    }

    function _setUpERC1155(address nftRecipient, address factoryCaller, address routerCaller)
        internal
        returns (IERC1155Mintable nft)
    {
        nft = setup1155();
        // Set royalties
        IRoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(nft), address(test2981));
        nft.mint(nftRecipient, ID_1155, END_INDEX + 1);
        vm.prank(factoryCaller);
        nft.setApprovalForAll(address(pairFactory), true);
        vm.prank(routerCaller);
        nft.setApprovalForAll(address(router), true);
    }

    function _getArray(uint256 start, uint256 end) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](end - start + 1);
        for (uint256 i = 0; i < ids.length; i++) {
            ids[i] = start + i;
        }
    }

    function setUpPairERC721ForSale(uint256 depositAmount, address _propertyChecker, uint256[] memory nftIdsToDeposit)
        public
        returns (LSSVMPair pair)
    {
        if (_propertyChecker == address(0)) {
            // Set up pair on behalf of pair creator
            pair = this.setupPairERC721{value: modifyInputAmount(depositAmount)}(
                pairFactory,
                IERC721(address(_setUpERC721(address(this), address(this), ROUTER_CALLER))),
                bondingCurve,
                payable(address(0)),
                LSSVMPair.PoolType.TRADE,
                delta,
                0, // fee
                spotPrice,
                nftIdsToDeposit,
                depositAmount,
                address(router)
            );
        } else {
            pair = this.setupPairWithPropertyCheckerERC721{value: modifyInputAmount(depositAmount)}(
                PairCreationParamsWithPropertyCheckerERC721({
                    factory: pairFactory,
                    nft: IERC721(address(_setUpERC721(address(this), address(this), ROUTER_CALLER))),
                    bondingCurve: bondingCurve,
                    assetRecipient: payable(address(0)),
                    poolType: LSSVMPair.PoolType.TRADE,
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
    }

    function setUpPairERC1155ForSale(
        uint256 depositAmount,
        uint256 numNFTsToDeposit,
        address nftRecipient,
        address factoryCaller,
        address routerCaller
    ) public returns (LSSVMPair pair) {
        IERC1155 nft = _setUpERC1155(nftRecipient, factoryCaller, routerCaller);
        pair = this.setupPairERC1155{value: modifyInputAmount(depositAmount)}(
            CreateERC1155PairParams({
                factory: pairFactory,
                nft: nft,
                bondingCurve: bondingCurve,
                assetRecipient: payable(address(0)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: delta,
                fee: 0, // fee
                spotPrice: spotPrice,
                nftId: ID_1155,
                initialNFTBalance: numNFTsToDeposit,
                initialTokenBalance: depositAmount,
                routerAddress: address(router)
            })
        );
    }

    function _getEmptyArrayWithLastValue(uint256 numItems, uint256 value)
        internal
        pure
        returns (uint256[] memory arr)
    {
        arr = new uint256[](numItems);
        arr[numItems - 1] = value;
    }

    function _getBuyOrderAllItemsAvailable(bool is721)
        internal
        returns (VeryFastRouter.BuyOrderWithPartialFill memory buyOrder, BuyResult memory result)
    {
        uint256[] memory nftIds;
        LSSVMPair pair;
        uint256 numNFTsForQuote = END_INDEX + 1;

        if (is721) {
            // Set up pair with empty property checker as PAIR_CREATOR
            nftIds = _getArray(START_INDEX, END_INDEX);
            pair = setUpPairERC721ForSale(0, address(0), nftIds);
        } else {
            // Set up ERC1155 pair
            pair = setUpPairERC1155ForSale(0, numNFTsForQuote, address(this), address(this), ROUTER_CALLER);

            // Set the first value to be the number of assets to swap
            nftIds = new uint256[](1);
            nftIds[0] = numNFTsForQuote;
        }

        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, numNFTsForQuote);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, numNFTsForQuote, SLIPPAGE, START_INDEX);

        // Assert that we are sending as many tokens as needed in the case where we fill everything
        assertApproxEqRel(inputAmount, partialFillAmounts[partialFillAmounts.length - 1], 1e9, "Difference too large");

        buyOrder = VeryFastRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftIds,
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice(),
            isERC721: is721,
            maxCostPerNumNFTs: partialFillAmounts
        });
        result = BuyResult({
            nftRecipient: ROUTER_CALLER,
            numItemsReceived: numNFTsForQuote,
            idsReceived: nftIds,
            pair: pair,
            isERC721: is721
        });
    }

    function _getBuyOrderNotAllItemsAvailableAllItemsInPrice(bool is721)
        internal
        returns (VeryFastRouter.BuyOrderWithPartialFill memory buyOrder, BuyResult memory result)
    {
        uint256 numNFTsToReceive = PARTIAL_FILL_INDEX + 1;
        uint256 numNFTsForQuote = END_INDEX + 1;
        uint256[] memory nftsInPair;
        uint256[] memory nftIds;
        LSSVMPair pair;

        if (is721) {
            // Set up pair with empty property checker as PAIR_CREATOR
            // Only deposit from START_INDEX to PARTIAL_FILL_INDEX number of items
            nftsInPair = _getArray(START_INDEX, PARTIAL_FILL_INDEX);
            pair = setUpPairERC721ForSale(0, address(0), nftsInPair);

            // Get set of all ids from START_INDEX to END_INDEX
            nftIds = _getArray(START_INDEX, END_INDEX);
        } else {
            pair = setUpPairERC1155ForSale(0, numNFTsToReceive, address(this), address(this), ROUTER_CALLER);
            // Set the first value to be the number of assets to swap
            nftIds = new uint256[](1);
            nftIds[0] = numNFTsForQuote;
        }

        // Still get the partial fill quotes
        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, numNFTsForQuote);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, numNFTsForQuote, SLIPPAGE, START_INDEX);

        // Construct the same buy order
        buyOrder = VeryFastRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftIds,
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice() + 1, // We increase by one to trigger the partial fill logic
            isERC721: is721,
            maxCostPerNumNFTs: partialFillAmounts
        });

        // Expected results now have only the nfts in the pair
        result = BuyResult({
            nftRecipient: address(this),
            numItemsReceived: numNFTsToReceive,
            idsReceived: nftsInPair,
            pair: pair,
            isERC721: is721
        });
    }

    function _getBuyOrderAllItemsAvailableNotAllItemsInPrice(bool is721)
        internal
        returns (VeryFastRouter.BuyOrderWithPartialFill memory buyOrder, BuyResult memory result)
    {
        LSSVMPair pair;
        uint256[] memory nftInfo;
        uint256 numNFTsToDeposit = END_INDEX + 1;

        // Set up pair with empty property checker as PAIR_CREATOR
        if (is721) {
            uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);
            pair = setUpPairERC721ForSale(0, address(0), nftIds);
            nftInfo = nftIds;
        } else {
            pair = setUpPairERC1155ForSale(0, numNFTsToDeposit, address(this), address(this), ROUTER_CALLER);
            // Set the first value to be the number of assets to swap
            nftInfo = new uint256[](1);
            nftInfo[0] = numNFTsToDeposit;
        }

        // Get the partial fill quotes
        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, numNFTsToDeposit);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, numNFTsToDeposit, SLIPPAGE, START_INDEX);

        // Assume that PARTIAL_FILL number of items have been bought
        (, uint256 newSpotPrice, uint256 newDelta,,,) = pair.getBuyNFTQuote(START_INDEX, PARTIAL_FILL_INDEX);

        // Set the spotPrice and delta to be the new values
        pair.changeDelta(uint128(newDelta));
        pair.changeSpotPrice(uint128(newSpotPrice));

        // Construct the buy order
        buyOrder = VeryFastRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftInfo,
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice() + 1, // We increase by one to trigger the partial fill logic
            isERC721: is721,
            maxCostPerNumNFTs: partialFillAmounts
        });

        // Expected results now have only the remaining NFTs
        uint256[] memory expectedNFTs = _getArray(START_INDEX, END_INDEX - PARTIAL_FILL_INDEX);

        // Construct the post swap results
        result = BuyResult({
            nftRecipient: address(this),
            numItemsReceived: expectedNFTs.length,
            idsReceived: expectedNFTs,
            pair: pair,
            isERC721: is721
        });
    }

    function _getBuyOrderNotAllitemsAvailableNotAllItemsInPrice(bool is721)
        internal
        returns (VeryFastRouter.BuyOrderWithPartialFill memory buyOrder, BuyResult memory result)
    {
        LSSVMPair pair;
        uint256[] memory nftInfo;
        uint256 numNFTsToDeposit = PARTIAL_FILL_INDEX + 1;
        uint256 numNFTsTotal = END_INDEX + 1;

        if (is721) {
            // Get only up to partial fill number of NFTs to deposit
            uint256[] memory nftsInPair = _getArray(START_INDEX, PARTIAL_FILL_INDEX);

            // Get set of all ids from START_INDEX to END_INDEX
            uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);

            // Set up pair with empty property checker as PAIR_CREATOR
            // Only deposit from START_INDEX to PARTIAL_FILL_INDEX number of items
            pair = setUpPairERC721ForSale(0, address(0), nftsInPair);

            nftInfo = nftIds;
        } else {
            pair = setUpPairERC1155ForSale(0, numNFTsToDeposit, address(this), address(this), ROUTER_CALLER);
            // Set the first value to be the number of assets to swap
            nftInfo = new uint256[](1);
            nftInfo[0] = numNFTsToDeposit;
        }

        // Get the partial fill quotes assuming we can buy all of the items
        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, numNFTsTotal);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, numNFTsTotal, SLIPPAGE, START_INDEX);

        // Assume that NUM_BEFORE_PARTIAL_FILL + PARTIAL_FILL number of items have been bought first
        (, uint256 newSpotPrice, uint256 newDelta,,,) =
            pair.getBuyNFTQuote(START_INDEX, PARTIAL_FILL_INDEX + NUM_BEFORE_PARTIAL_FILL);

        // Set the spotPrice and delta to be the new values assuming this change
        pair.changeDelta(uint128(newDelta));
        pair.changeSpotPrice(uint128(newSpotPrice));

        // Construct the buy order
        buyOrder = VeryFastRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftInfo, // Attempt to get all of the NFT IDs
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice() + 1, // We increase by one to trigger the partial fill logic
            isERC721: is721,
            maxCostPerNumNFTs: partialFillAmounts
        });

        // Expected results now have only the nfts in the pair, but only some of them
        uint256[] memory actualReceivedNFTs = _getArray(START_INDEX, PARTIAL_FILL_INDEX - NUM_BEFORE_PARTIAL_FILL);
        result = BuyResult({
            nftRecipient: address(this),
            numItemsReceived: actualReceivedNFTs.length,
            idsReceived: actualReceivedNFTs,
            pair: pair,
            isERC721: is721
        });
    }

    function _getBuyOrderAllItemsUnavailable(bool is721)
        internal
        returns (VeryFastRouter.BuyOrderWithPartialFill memory buyOrder, BuyResult memory result)
    {
        uint256[] memory nftInfo;
        uint256 numNFTsTotal = END_INDEX + 1;
        uint256[] memory emptyList = new uint256[](0);
        LSSVMPair pair;

        if (is721) {
            // Get set of all ids from START_INDEX to END_INDEX
            uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);
            nftInfo = nftIds;

            // Set up pair with empty property checker as PAIR_CREATOR
            // Deposit none of the NFTs
            pair = setUpPairERC721ForSale(0, address(0), emptyList);
        } else {
            // Deposit no NFTs
            pair = setUpPairERC1155ForSale(0, 0, address(this), address(this), ROUTER_CALLER);
            // Set the first value to be the number of assets to swap
            nftInfo = new uint256[](1);
            nftInfo[0] = numNFTsTotal;
        }

        // Get the partial fill quotes assuming we can buy all of the items
        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, numNFTsTotal);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, numNFTsTotal, SLIPPAGE, START_INDEX);

        // Construct the buy order
        buyOrder = VeryFastRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftInfo, // Attempt to get all of the NFT IDs
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice() + 1, // We increase by one to trigger the partial fill logic
            isERC721: is721,
            maxCostPerNumNFTs: partialFillAmounts
        });

        // Expected results now have no NFTs
        result = BuyResult({
            nftRecipient: address(this),
            numItemsReceived: 0,
            idsReceived: emptyList,
            pair: pair,
            isERC721: is721
        });
    }

    function _getBuyOrderAllItemsNotInPrice(bool is721)
        internal
        returns (VeryFastRouter.BuyOrderWithPartialFill memory buyOrder, BuyResult memory result)
    {
        uint256[] memory nftInfo;
        uint256 numNFTsTotal = END_INDEX + 1;
        LSSVMPair pair;

        if (is721) {
            uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);
            nftInfo = nftIds;
            pair = setUpPairERC721ForSale(0, address(0), nftIds);
        } else {
            // Deposit no NFTs
            pair = setUpPairERC1155ForSale(numNFTsTotal, 0, address(this), address(this), ROUTER_CALLER);
            // Set the first value to be the number of assets to swap
            nftInfo = new uint256[](1);
            nftInfo[0] = numNFTsTotal;
        }

        // Get the partial fill quotes
        (,,, uint256 inputAmount,,) = pair.getBuyNFTQuote(START_INDEX, numNFTsTotal);
        uint256[] memory partialFillAmounts =
            router.getNFTQuoteForBuyOrderWithPartialFill(pair, numNFTsTotal, SLIPPAGE, START_INDEX);

        // Assume that *all* items have been bought
        (, uint256 newSpotPrice, uint256 newDelta,,,) = pair.getBuyNFTQuote(START_INDEX, END_INDEX + 1);

        // Set the spotPrice and delta to be the new values
        pair.changeDelta(uint128(newDelta));
        pair.changeSpotPrice(uint128(newSpotPrice));

        // Construct the buy order
        buyOrder = VeryFastRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftInfo, // Attempt to get all of the NFT IDs
            maxInputAmount: inputAmount,
            ethAmount: modifyInputAmount(inputAmount),
            expectedSpotPrice: pair.spotPrice() + 1, // We increase by one to trigger the partial fill logic
            isERC721: is721,
            maxCostPerNumNFTs: partialFillAmounts
        });

        // Expected results now have no NFTs
        uint256[] memory emptyList = new uint256[](0);
        result = BuyResult({
            nftRecipient: address(this),
            numItemsReceived: 0,
            idsReceived: emptyList,
            pair: pair,
            isERC721: is721
        });
    }

    function _getBuyOrder(BuySwap swapType)
        internal
        returns (VeryFastRouter.BuyOrderWithPartialFill memory buyOrder, BuyResult memory result)
    {
        if (swapType == BuySwap.ITEM_PARTIAL_PRICE_FULL_721) {
            return _getBuyOrderNotAllItemsAvailableAllItemsInPrice(true);
        } else if (swapType == BuySwap.ITEM_FULL_PRICE_FULL_721) {
            return _getBuyOrderAllItemsAvailable(true);
        } else if (swapType == BuySwap.ITEM_FULL_PRICE_PARTIAL_721) {
            return _getBuyOrderAllItemsAvailableNotAllItemsInPrice(true);
        } else if (swapType == BuySwap.ITEM_PARTIAL_PRICE_PARTIAL_721) {
            return _getBuyOrderNotAllitemsAvailableNotAllItemsInPrice(true);
        } else if (swapType == BuySwap.ITEM_NONE_PRICE_FULL_721) {
            return _getBuyOrderAllItemsUnavailable(true);
        } else if (swapType == BuySwap.ITEM_FULL_PRICE_NONE_721) {
            return _getBuyOrderAllItemsNotInPrice(true);
        }
        // 1155 test variants start here
        else if (swapType == BuySwap.ITEM_FULL_PRICE_FULL_1155) {
            return _getBuyOrderAllItemsAvailable(false);
        } else if (swapType == BuySwap.ITEM_PARTIAL_PRICE_FULL_1155) {
            return _getBuyOrderNotAllItemsAvailableAllItemsInPrice(false);
        } else if (swapType == BuySwap.ITEM_FULL_PRICE_PARTIAL_1155) {
            return _getBuyOrderAllItemsAvailableNotAllItemsInPrice(false);
        } else if (swapType == BuySwap.ITEM_PARTIAL_PRICE_PARTIAL_1155) {
            return _getBuyOrderNotAllitemsAvailableNotAllItemsInPrice(false);
        } else if (swapType == BuySwap.ITEM_NONE_PRICE_FULL_1155) {
            return _getBuyOrderAllItemsUnavailable(false);
        } else if (swapType == BuySwap.ITEM_FULL_PRICE_NONE_1155) {
            return _getBuyOrderAllItemsNotInPrice(false);
        }
    }

    function _getSellOrderFullPriceFullBalance(bool doPropertyCheck, bool is721)
        internal
        returns (VeryFastRouter.SellOrderWithPartialFill memory sellOrder, SellResult memory result)
    {
        address propertyCheckerAddress = address(0);

        if (doPropertyCheck) {
            propertyCheckerAddress = address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, END_INDEX));
        }

        LSSVMPair pair;
        uint256[] memory nftInfo;
        uint256[] memory emptyList = new uint256[](0);
        uint256 numNFTsForQuote = END_INDEX + 1;

        if (is721) {
            // Set up pair with no tokens
            pair = setUpPairERC721ForSale(0, propertyCheckerAddress, emptyList);

            // Get array of all NFT IDs we want to sell
            uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);
            nftInfo = nftIds;
        } else {
            pair = setUpPairERC1155ForSale(0, 0, address(ROUTER_CALLER), address(ROUTER_CALLER), address(ROUTER_CALLER));
            nftInfo = new uint256[](1);
            nftInfo[0] = numNFTsForQuote;
        }

        // Get the amount needed to put in the pair
        (,,, uint256 outputAmount,, uint256 protocolFee) = pair.bondingCurve().getSellInfo(
            pair.spotPrice(), pair.delta(), numNFTsForQuote, pair.fee(), pair.factory().protocolFeeMultiplier()
        );

        // Send that many tokens to the pair
        sendTokens(pair, outputAmount + protocolFee);

        // Calculate how many tokens we actually get
        (,,, uint256 expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, numNFTsForQuote);

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Construct the sell order
        sellOrder = VeryFastRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: is721,
            nftIds: nftInfo,
            doPropertyCheck: doPropertyCheck,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice(),
            minExpectedOutput: expectedOutput,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(
                pair, numNFTsForQuote, SLIPPAGE, START_INDEX
                )
        });

        result = SellResult({
            nftRecipient: address(pair),
            numItemsReceived: numNFTsForQuote,
            idsReceived: nftInfo,
            pair: pair,
            isERC721: is721,
            tokenRecipient: TOKEN_RECIPIENT,
            tokenBalance: expectedOutput
        });
    }

    function _getSellOrderFullPricePartialBalance(bool doPropertyCheck, bool is721)
        internal
        returns (VeryFastRouter.SellOrderWithPartialFill memory sellOrder, SellResult memory result)
    {
        address propertyCheckerAddress = address(0);

        if (doPropertyCheck) {
            propertyCheckerAddress = address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, END_INDEX));
        }

        LSSVMPair pair;
        uint256[] memory nftInfo;
        uint256 numNFTsTotal = END_INDEX + 1;

        // Set up pair with no tokens
        if (is721) {
            // Get array of all NFT IDs we want to sell
            uint256[] memory nftIds = _getArray(START_INDEX, END_INDEX);
            nftInfo = nftIds;
            pair = setUpPairERC721ForSale(0, propertyCheckerAddress, new uint256[](0));
        } else {
            pair = setUpPairERC1155ForSale(0, 0, address(ROUTER_CALLER), address(ROUTER_CALLER), address(ROUTER_CALLER));
            nftInfo = new uint256[](1);
            nftInfo[0] = numNFTsTotal;
        }

        // Get the amount needed to put in the pair to support only selling up to the partial fill amount
        (,,, uint256 outputAmount,, uint256 protocolFee) = pair.bondingCurve().getSellInfo(
            pair.spotPrice(), pair.delta(), PARTIAL_FILL_INDEX + 1, pair.fee(), pair.factory().protocolFeeMultiplier()
        );

        // Send that many tokens to the pair
        sendTokens(pair, outputAmount + protocolFee);

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Construct the sell order
        // Calculate the max amount we can receive
        (,,, uint256 expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, numNFTsTotal);
        sellOrder = VeryFastRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: is721,
            nftIds: nftInfo,
            doPropertyCheck: doPropertyCheck,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice() + 1, // Trigger partial fill
            minExpectedOutput: expectedOutput,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(
                pair, numNFTsTotal, SLIPPAGE, START_INDEX
                )
        });

        // Calculate how many tokens we actually expect to get
        (,,, expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, PARTIAL_FILL_INDEX + 1);
        result = SellResult({
            nftRecipient: address(pair),
            numItemsReceived: PARTIAL_FILL_INDEX + 1,
            idsReceived: _getArray(START_INDEX, PARTIAL_FILL_INDEX),
            pair: pair,
            isERC721: is721,
            tokenRecipient: TOKEN_RECIPIENT,
            tokenBalance: expectedOutput
        });
    }

    function _getSellOrderPartialPriceFullBalance(bool doPropertyCheck, bool is721)
        internal
        returns (VeryFastRouter.SellOrderWithPartialFill memory sellOrder, SellResult memory result)
    {
        address propertyCheckerAddress = address(0);

        if (doPropertyCheck) {
            propertyCheckerAddress = address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, END_INDEX));
        }

        LSSVMPair pair;
        uint256[] memory nftInfo;
        uint256 numNFTsTotal = END_INDEX + 1;

        if (is721) {
            pair = setUpPairERC721ForSale(0, propertyCheckerAddress, new uint256[](0));
            nftInfo = _getArray(START_INDEX, END_INDEX);
        } else {
            pair = setUpPairERC1155ForSale(0, 0, address(ROUTER_CALLER), address(ROUTER_CALLER), address(ROUTER_CALLER));
            nftInfo = new uint256[](1);
            nftInfo[0] = numNFTsTotal;
        }

        // Locally scope to avoid stack too deep
        {
            // Get the amount needed to put in the pair to support only selling all
            (,,, uint256 outputAmount,, uint256 protocolFee) = pair.bondingCurve().getSellInfo(
                pair.spotPrice(), pair.delta(), numNFTsTotal, pair.fee(), pair.factory().protocolFeeMultiplier()
            );

            // Send that many tokens to the pair
            sendTokens(pair, outputAmount + protocolFee);
        }

        // Get new spot price and delta as if we had sold NUM_BEFORE_PARTIAL_FILL number of NFTs
        (, uint128 newSpotPrice, uint128 newDelta,,,) = pair.bondingCurve().getSellInfo(
            pair.spotPrice(), pair.delta(), NUM_BEFORE_PARTIAL_FILL, pair.fee(), pair.factory().protocolFeeMultiplier()
        );

        bool isETHSell = true;
        if (getTokenAddress() != address(0)) {
            isETHSell = false;
        }

        // Construct the sell order
        // Calculate the max amount we can receive
        (,,, uint256 expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, numNFTsTotal);
        sellOrder = VeryFastRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: is721,
            nftIds: nftInfo,
            doPropertyCheck: doPropertyCheck,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice() + 1, // Trigger partial fill calculation
            minExpectedOutput: expectedOutput,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(
                pair, numNFTsTotal, SLIPPAGE, START_INDEX
                )
        });

        // Set the spotPrice and delta to be the new values (after calculating partial fill calculations)
        pair.changeDelta(uint128(newDelta));
        pair.changeSpotPrice(uint128(newSpotPrice));

        // Calculate how many tokens we actually expect to get
        (,,, expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, numNFTsTotal - NUM_BEFORE_PARTIAL_FILL);
        result = SellResult({
            nftRecipient: address(pair),
            numItemsReceived: numNFTsTotal - NUM_BEFORE_PARTIAL_FILL,
            idsReceived: _getArray(START_INDEX, numNFTsTotal - NUM_BEFORE_PARTIAL_FILL - 1),
            pair: pair,
            isERC721: is721,
            tokenRecipient: TOKEN_RECIPIENT,
            tokenBalance: expectedOutput
        });
    }

    function _getSellOrderPartialPricePartialBalance(bool doPropertyCheck, bool is721)
        internal
        returns (VeryFastRouter.SellOrderWithPartialFill memory sellOrder, SellResult memory result)
    {
        LSSVMPair pair;
        uint256[] memory nftInfo;

        if (is721) {
            address propertyCheckerAddress = address(0);
            if (doPropertyCheck) {
                propertyCheckerAddress =
                    address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, END_INDEX));
            }
            // Set up pair with no tokens
            pair = setUpPairERC721ForSale(0, propertyCheckerAddress, new uint256[](0));

            nftInfo = _getArray(START_INDEX, END_INDEX);
        } else {
            pair = setUpPairERC1155ForSale(0, 0, address(ROUTER_CALLER), address(ROUTER_CALLER), address(ROUTER_CALLER));
            nftInfo = new uint256[](1);
            nftInfo[0] = END_INDEX + 1;
        }

        {
            // Get the amount needed to put in the pair to support only selling up to the partial fill amount
            (,,, uint256 outputAmount,, uint256 protocolFee) = pair.bondingCurve().getSellInfo(
                pair.spotPrice(),
                pair.delta(),
                PARTIAL_FILL_INDEX + 1,
                pair.fee(),
                pair.factory().protocolFeeMultiplier()
            );

            // Send that many tokens to the pair
            sendTokens(pair, outputAmount + protocolFee);
        }

        // Get new spot price and delta as if we had sold NUM_BEFORE_PARTIAL_FILL number of NFTs
        (, uint128 newSpotPrice, uint128 newDelta,,,) = pair.bondingCurve().getSellInfo(
            pair.spotPrice(), pair.delta(), NUM_BEFORE_PARTIAL_FILL, pair.fee(), pair.factory().protocolFeeMultiplier()
        );

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Construct the sell order
        // Calculate the max amount we can receive
        (,,, uint256 expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, _getArray(START_INDEX, END_INDEX).length);
        sellOrder = VeryFastRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: is721,
            nftIds: nftInfo,
            doPropertyCheck: doPropertyCheck,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice() + 1, // Trigger partial fill calculation
            minExpectedOutput: expectedOutput,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(
                pair, _getArray(START_INDEX, END_INDEX).length, SLIPPAGE, START_INDEX
                )
        });

        // Set the spotPrice and delta to be the new values (after calculating partial fill calculations)
        pair.changeDelta(uint128(newDelta));
        pair.changeSpotPrice(uint128(newSpotPrice));

        // Calculate how many tokens we actually expect to get
        (,,, expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, PARTIAL_FILL_INDEX + 1);
        result = SellResult({
            nftRecipient: address(pair),
            numItemsReceived: PARTIAL_FILL_INDEX + 1,
            idsReceived: _getArray(START_INDEX, PARTIAL_FILL_INDEX),
            pair: pair,
            isERC721: is721,
            tokenRecipient: TOKEN_RECIPIENT,
            tokenBalance: expectedOutput
        });
    }

    function _getSellOrderPartialPriceNoBalance(bool doPropertyCheck, bool is721)
        internal
        returns (VeryFastRouter.SellOrderWithPartialFill memory sellOrder, SellResult memory result)
    {
        LSSVMPair pair;
        uint256[] memory nftInfo;

        if (is721) {
            address propertyCheckerAddress = address(0);
            if (doPropertyCheck) {
                propertyCheckerAddress =
                    address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, END_INDEX));
            }
            pair = setUpPairERC721ForSale(0, propertyCheckerAddress, new uint256[](0));
            nftInfo = _getArray(START_INDEX, END_INDEX);
        } else {
            pair = setUpPairERC1155ForSale(0, 0, address(ROUTER_CALLER), address(ROUTER_CALLER), address(ROUTER_CALLER));
            nftInfo = new uint256[](1);
            nftInfo[0] = END_INDEX + 1;
        }

        // We send no tokens to the pair

        // Get new spot price and delta as if we had sold NUM_BEFORE_PARTIAL_FILL number of NFTs
        (, uint128 newSpotPrice, uint128 newDelta,,,) = pair.bondingCurve().getSellInfo(
            pair.spotPrice(), pair.delta(), NUM_BEFORE_PARTIAL_FILL, pair.fee(), pair.factory().protocolFeeMultiplier()
        );

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Construct the sell order
        // Calculate the max amount we can receive
        (,,, uint256 expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, _getArray(START_INDEX, END_INDEX).length);
        sellOrder = VeryFastRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: is721,
            nftIds: nftInfo,
            doPropertyCheck: doPropertyCheck,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice() + 1, // Trigger partial fill calculation
            minExpectedOutput: expectedOutput,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(
                pair, _getArray(START_INDEX, END_INDEX).length, SLIPPAGE, START_INDEX
                )
        });

        // Set the spotPrice and delta to be the new values (after calculating partial fill calculations)
        pair.changeDelta(uint128(newDelta));
        pair.changeSpotPrice(uint128(newSpotPrice));

        // Expect to get nothing
        uint256[] memory emptyArr = new uint256[](0);
        result = SellResult({
            nftRecipient: address(pair),
            numItemsReceived: 0,
            idsReceived: emptyArr,
            pair: pair,
            isERC721: is721,
            tokenRecipient: TOKEN_RECIPIENT,
            tokenBalance: 0
        });
    }

    function _getSellOrderPriceNoneFullBalance(bool doPropertyCheck, bool is721)
        internal
        returns (VeryFastRouter.SellOrderWithPartialFill memory sellOrder, SellResult memory result)
    {
        LSSVMPair pair;
        uint256[] memory nftInfo;

        if (is721) {
            address propertyCheckerAddress = address(0);
            if (doPropertyCheck) {
                propertyCheckerAddress =
                    address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, END_INDEX));
            }
            pair = setUpPairERC721ForSale(0, propertyCheckerAddress, new uint256[](0));
            nftInfo = _getArray(START_INDEX, END_INDEX);
        } else {
            pair = setUpPairERC1155ForSale(0, 0, address(ROUTER_CALLER), address(ROUTER_CALLER), address(ROUTER_CALLER));
            nftInfo = new uint256[](1);
            nftInfo[0] = END_INDEX + 1;
        }

        // Get the amount needed to put in the pair to support selling everything (i.e. more than we need)
        // Get new spot price and delta as if we had sold END_INDEX number of NFTs
        (, uint128 newSpotPrice, uint128 newDelta, uint256 outputAmount,, uint256 protocolFee) = pair.bondingCurve()
            .getSellInfo(pair.spotPrice(), pair.delta(), END_INDEX + 1, pair.fee(), pair.factory().protocolFeeMultiplier());

        // Send that many tokens to the pair
        sendTokens(pair, outputAmount + protocolFee);

        bool isETHSell = true;
        address tokenAddress = getTokenAddress();
        if (tokenAddress != address(0)) {
            isETHSell = false;
        }

        // Construct the sell order
        // Calculate the max amount we can receive
        (,,, uint256 expectedOutput,,) = pair.getSellNFTQuote(START_INDEX, _getArray(START_INDEX, END_INDEX).length);
        sellOrder = VeryFastRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: isETHSell,
            isERC721: is721,
            nftIds: _getArray(START_INDEX, END_INDEX),
            doPropertyCheck: doPropertyCheck,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice() + 1, // Trigger partial fill calculation
            minExpectedOutput: expectedOutput,
            minExpectedOutputPerNumNFTs: router.getNFTQuoteForSellOrderWithPartialFill(
                pair, _getArray(START_INDEX, END_INDEX).length, SLIPPAGE, START_INDEX
                )
        });

        // Set the spotPrice and delta to be the new values (after calculating partial fill calculations)
        // (i.e. set spot price and delta to be assuming we've sold all the items)
        pair.changeDelta(uint128(newDelta));
        pair.changeSpotPrice(uint128(newSpotPrice));

        // Expect to get nothing
        uint256[] memory emptyArr = new uint256[](0);
        result = SellResult({
            nftRecipient: address(pair),
            numItemsReceived: 0,
            idsReceived: emptyArr,
            pair: pair,
            isERC721: is721,
            tokenRecipient: TOKEN_RECIPIENT,
            tokenBalance: 0
        });
    }

    function _getSellOrder(SellSwap swapType, bool doPropertyCheck)
        internal
        returns (VeryFastRouter.SellOrderWithPartialFill memory sellOrder, SellResult memory result)
    {
        if (swapType == SellSwap.PRICE_FULL_BALANCE_FULL_721) {
            return _getSellOrderFullPriceFullBalance(doPropertyCheck, true);
        } else if (swapType == SellSwap.PRICE_FULL_BALANCE_PARTIAL_721) {
            return _getSellOrderFullPricePartialBalance(doPropertyCheck, true);
        } else if (swapType == SellSwap.PRICE_PARTIAL_BALANCE_FULL_721) {
            return _getSellOrderPartialPriceFullBalance(doPropertyCheck, true);
        } else if (swapType == SellSwap.PRICE_PARTIAL_BALANCE_PARTIAL_721) {
            return _getSellOrderPartialPricePartialBalance(doPropertyCheck, true);
        } else if (swapType == SellSwap.PRICE_PARTIAL_BALANCE_NONE_721) {
            return _getSellOrderPartialPriceNoBalance(doPropertyCheck, true);
        } else if (swapType == SellSwap.PRICE_NONE_BALANCE_FULL_721) {
            return _getSellOrderPriceNoneFullBalance(doPropertyCheck, true);
        }
        // 1155 tests begin here
        else if (swapType == SellSwap.PRICE_FULL_BALANCE_FULL_1155) {
            return _getSellOrderFullPriceFullBalance(false, false);
        } else if (swapType == SellSwap.PRICE_FULL_BALANCE_PARTIAL_1155) {
            return _getSellOrderFullPricePartialBalance(false, false);
        } else if (swapType == SellSwap.PRICE_PARTIAL_BALANCE_FULL_1155) {
            return _getSellOrderPartialPriceFullBalance(false, false);
        } else if (swapType == SellSwap.PRICE_PARTIAL_BALANCE_PARTIAL_1155) {
            return _getSellOrderPartialPricePartialBalance(false, false);
        } else if (swapType == SellSwap.PRICE_PARTIAL_BALANCE_NONE_1155) {
            return _getSellOrderPartialPriceNoBalance(false, false);
        } else if (swapType == SellSwap.PRICE_NONE_BALANCE_FULL_1155) {
            return _getSellOrderPriceNoneFullBalance(false, false);
        }
    }

    // Do all the swap combos
    function testSwap() public {
        // Construct buy orders
        uint256 totalETHToSend = 0;
        uint256 numBuySwapTypes = uint256(type(BuySwap).max) + 1;

        BuyResult[] memory buyResults = new BuyResult[](numBuySwapTypes);
        VeryFastRouter.BuyOrderWithPartialFill[] memory buyOrders =
            new VeryFastRouter.BuyOrderWithPartialFill[](numBuySwapTypes);
        for (uint256 i = 0; i < numBuySwapTypes; i++) {
            (VeryFastRouter.BuyOrderWithPartialFill memory buyOrder, BuyResult memory result) = _getBuyOrder(BuySwap(i));
            buyOrders[i] = buyOrder;
            totalETHToSend += buyOrder.ethAmount;
            buyResults[i] = result;
        }

        // Modify the ETH amount to send depending on if ETH or ERC20
        totalETHToSend = modifyInputAmount(totalETHToSend);

        // Construct sell orders
        uint256 numSellSwapTypes = uint256(type(SellSwap).max) + 1;

        // @dev the below 2 arrays are 2x the numSellSwapTypes because we have doPropertyCheck vs not doPropertyCheck
        SellResult[] memory sellResults = new SellResult[](numSellSwapTypes * 2);
        VeryFastRouter.SellOrderWithPartialFill[] memory sellOrders =
            new VeryFastRouter.SellOrderWithPartialFill[](numSellSwapTypes * 2);

        for (uint256 flag = 0; flag < 2; flag++) {
            bool doPropertyCheck = flag == 0;
            for (uint256 i = 0; i < numSellSwapTypes; i++) {
                uint256 index = flag * numSellSwapTypes + i;
                (VeryFastRouter.SellOrderWithPartialFill memory sellOrder, SellResult memory result) =
                    _getSellOrder(SellSwap(i), doPropertyCheck);
                sellOrders[index] = sellOrder;
                sellResults[index] = result;

                // Prank as the router caller and set approval for the router
                vm.prank(ROUTER_CALLER);
                IERC721(sellOrder.pair.nft()).setApprovalForAll(address(router), true);

                // Send the required NFTs to the router caller
                if (sellOrder.isERC721) {
                    for (uint256 j = 0; j < sellOrder.nftIds.length; j++) {
                        IERC721(sellOrder.pair.nft()).transferFrom(address(this), ROUTER_CALLER, sellOrder.nftIds[j]);
                    }
                }
            }
        }

        // Set up the actual VFR swap
        VeryFastRouter.Order memory swapOrder = VeryFastRouter.Order({
            buyOrders: buyOrders,
            sellOrders: sellOrders,
            tokenRecipient: payable(address(TOKEN_RECIPIENT)),
            nftRecipient: NFT_RECIPIENT,
            recycleETH: false
        });

        // Prank as the router caller and do the swap
        vm.startPrank(ROUTER_CALLER);
        address tokenAddress = getTokenAddress();

        // Set up approval for token if it is a token pair (for router caller)
        if (tokenAddress != address(0)) {
            ERC20(tokenAddress).approve(address(router), 1e18 ether);
            IMintable(tokenAddress).mint(ROUTER_CALLER, 1e18 ether);
        }

        // Store the swap results
        uint256[] memory swapResults = router.swap{value: totalETHToSend}(swapOrder);
        vm.stopPrank();

        // Validate all of the buy results
        for (uint256 i; i < buyResults.length; i++) {
            BuyResult memory result = buyResults[i];

            // Assert the owned items are as expected
            if (result.isERC721) {
                assertEq(IERC721(result.pair.nft()).balanceOf(NFT_RECIPIENT), result.numItemsReceived);

                for (uint256 j; j < result.idsReceived.length; j++) {
                    assertEq(IERC721(result.pair.nft()).ownerOf(result.idsReceived[j]), NFT_RECIPIENT);
                }
            }
            // Otherwise, if 1155, do a balance check for the recipient
            else {
                assertEq(IERC1155(result.pair.nft()).balanceOf(NFT_RECIPIENT, ID_1155), result.numItemsReceived);
            }
        }

        // Validate all of the sell results
        for (uint256 i; i < sellResults.length; i++) {
            SellResult memory result = sellResults[i];

            // Verify swap balance
            assertEq(swapResults[i], result.tokenBalance);

            // Assert the owned items are owned by the pair as expected
            if (result.isERC721) {
                assertEq(IERC721(result.pair.nft()).balanceOf(address(result.pair)), result.numItemsReceived);

                for (uint256 j; j < result.idsReceived.length; j++) {
                    assertEq(IERC721(result.pair.nft()).ownerOf(result.idsReceived[j]), address(result.pair));
                }
            }
        }
    }

    function _getRecycleOrder(bool doPropertyCheck, bool is721)
        public
        returns (
            VeryFastRouter.SellOrderWithPartialFill memory sellOrder,
            VeryFastRouter.BuyOrderWithPartialFill memory buyOrder,
            uint256 difference
        )
    {
        LSSVMPair pair;
        uint256[] memory nftInfo;
        uint256 numNFTsTotal = END_INDEX_RECYCLE + 1;
        if (is721) {
            address propertyCheckerAddress = address(0);
            if (doPropertyCheck) {
                propertyCheckerAddress =
                    address(propertyCheckerFactory.createRangePropertyChecker(START_INDEX, END_INDEX_RECYCLE));
            }
            // Set up pair with no tokens
            pair = setUpPairERC721ForSale(0, propertyCheckerAddress, new uint256[](0));
            nftInfo = _getArray(START_INDEX, END_INDEX_RECYCLE);
        } else {
            pair = setUpPairERC1155ForSale(0, 0, address(ROUTER_CALLER), address(ROUTER_CALLER), address(ROUTER_CALLER));
            nftInfo = new uint256[](1);
            nftInfo[0] = numNFTsTotal;
        }

        // Get the amount needed to put in the pair to accommodate for nftIds.length sells
        (, uint128 newSpotPrice, uint128 newDelta, uint256 outputAmount,, uint256 protocolFee) = pair.bondingCurve()
            .getSellInfo(pair.spotPrice(), pair.delta(), numNFTsTotal, pair.fee(), pair.factory().protocolFeeMultiplier());

        outputAmount = outputAmount + protocolFee;

        // Send that many tokens to the pair
        sendTokens(pair, outputAmount);

        // Subtract outputAmount down by the royaltyAmount so we can use it later for accurate pricing in
        // minExpectedTokenOutput
        {
            uint256 royaltyTotal;
            (,, royaltyTotal) = pair.calculateRoyaltiesView(START_INDEX, outputAmount);
            outputAmount -= royaltyTotal;
        }

        // Calculate the amount needed to buy back numNFTsTotal nfts in the new state
        (,,, uint256 inputAmount,,) = pair.bondingCurve().getBuyInfo(
            newSpotPrice, newDelta, numNFTsTotal, pair.fee(), pair.factory().protocolFeeMultiplier()
        );

        // Add up for the royalty amount
        // (no need to handle protocol fee, the getBuyInfo already accounts for it)
        {
            uint256 royaltyTotal;
            (,, royaltyTotal) = pair.calculateRoyaltiesView(START_INDEX, inputAmount);
            inputAmount += royaltyTotal;
        }

        // Set up additional amount to send to account for royalty amount
        difference = inputAmount - outputAmount;

        // Scale up slightly to account for numerical issues
        difference = difference * 1001 / 1000;

        // Construct sell order
        sellOrder = VeryFastRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: true,
            isERC721: is721,
            nftIds: nftInfo,
            doPropertyCheck: doPropertyCheck,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice(),
            minExpectedOutput: outputAmount,
            minExpectedOutputPerNumNFTs: _getEmptyArrayWithLastValue(numNFTsTotal, outputAmount)
        });

        uint256[] memory maxCostPerNumNFTs = new uint256[](numNFTsTotal);
        maxCostPerNumNFTs[numNFTsTotal - 1] = inputAmount;

        // Construct buy order
        buyOrder = VeryFastRouter.BuyOrderWithPartialFill({
            pair: pair,
            nftIds: nftInfo,
            maxInputAmount: inputAmount,
            ethAmount: inputAmount,
            expectedSpotPrice: pair.spotPrice(),
            isERC721: is721,
            maxCostPerNumNFTs: _getEmptyArrayWithLastValue(numNFTsTotal, inputAmount)
        });
    }

    // Test recycling ETH
    function testRecycleETH() public {
        VeryFastRouter.SellOrderWithPartialFill[] memory sellOrders = new VeryFastRouter.SellOrderWithPartialFill[](3);
        VeryFastRouter.BuyOrderWithPartialFill[] memory buyOrders = new VeryFastRouter.BuyOrderWithPartialFill[](3);

        uint256 totalDifferenceToSend = 0;

        for (uint256 flag = 0; flag < 2; flag++) {
            bool doPropertyCheck = flag == 0;
            (
                VeryFastRouter.SellOrderWithPartialFill memory sellOrder,
                VeryFastRouter.BuyOrderWithPartialFill memory buyOrder,
                uint256 differenceToSend
            ) = _getRecycleOrder(doPropertyCheck, true);
            sellOrders[flag] = sellOrder;
            buyOrders[flag] = buyOrder;
            totalDifferenceToSend += differenceToSend;

            // Send the required NFTs to the router caller
            for (uint256 j = 0; j < sellOrder.nftIds.length; j++) {
                IERC721(sellOrder.pair.nft()).transferFrom(address(this), ROUTER_CALLER, sellOrder.nftIds[j]);
            }
        }

        // Add 1155 swap to the array of buys and sells
        (
            VeryFastRouter.SellOrderWithPartialFill memory sellOrder1155,
            VeryFastRouter.BuyOrderWithPartialFill memory buyOrder1155,
            uint256 differenceToSend1155
        ) = _getRecycleOrder(false, false);
        sellOrders[2] = sellOrder1155;
        buyOrders[2] = buyOrder1155;
        totalDifferenceToSend += differenceToSend1155;

        // Set up the actual VFR swap
        VeryFastRouter.Order memory swapOrder = VeryFastRouter.Order({
            buyOrders: buyOrders,
            sellOrders: sellOrders,
            tokenRecipient: payable(address(TOKEN_RECIPIENT)),
            nftRecipient: NFT_RECIPIENT,
            recycleETH: true
        });

        // Prank as the router caller and do the swap
        vm.startPrank(ROUTER_CALLER);

        // Only run if it's an ETH pair
        if (getTokenAddress() == address(0)) {
            // The swap should succeed
            router.swap{value: totalDifferenceToSend}(swapOrder);
        }
        vm.stopPrank();
    }
}
