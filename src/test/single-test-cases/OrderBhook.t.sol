// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

import {Test2981} from "../../mocks/Test2981.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {MockCurve} from "../../mocks/MockCurve.sol";
import {Test20} from "../../mocks/Test20.sol";
import {Test721} from "../../mocks/Test721.sol";
import {Test1155} from "../../mocks/Test1155.sol";

import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {IERC1155Mintable} from "../interfaces/IERC1155Mintable.sol";
import {IPropertyChecker} from "../../property-checking/IPropertyChecker.sol";
import {RangePropertyChecker} from "../../property-checking/RangePropertyChecker.sol";
import {MerklePropertyChecker} from "../../property-checking/MerklePropertyChecker.sol";
import {PropertyCheckerFactory} from "../../property-checking/PropertyCheckerFactory.sol";

import {UsingETH} from "../mixins/UsingETH.sol";
import {UsingLinearCurve} from "../../test/mixins/UsingLinearCurve.sol";
import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {LSSVMPairETH} from "../../LSSVMPairETH.sol";
import {ILSSVMPair} from "../../ILSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {VeryFastRouter} from "../../VeryFastRouter.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";

import {GDACurve} from "../../bonding-curves/GDACurve.sol";
import {LinearCurve} from "../../bonding-curves/LinearCurve.sol";

import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";

import {DummyHooks} from "../../hooks/DummyHooks.sol";
import {OrderBhook} from "../../hooks/OrderBhook.sol";

contract OrderBhookTest is Test, ConfigurableWithRoyalties, UsingLinearCurve, UsingETH, ERC1155Holder, ERC721Holder {
    using SafeTransferLib for address payable;

    ICurve linearCurve;
    ICurve gdaCurve;
    RoyaltyEngine royaltyEngine;
    LSSVMPairFactory pairFactory;
    PropertyCheckerFactory propertyCheckerFactory;
    VeryFastRouter router;
    IERC721 test721;

    OrderBhook bhook;

    function setUp() public {
        linearCurve = setupCurve();
        gdaCurve = new GDACurve();

        royaltyEngine = setupRoyaltyEngine();
        ERC2981 royaltyLookup = ERC2981(new Test2981(payable(address(this)), 0));

        test721 = setup721();

        pairFactory = setupFactory(royaltyEngine, payable(address(0)));
        pairFactory.setBondingCurveAllowed(linearCurve, true);
        pairFactory.setBondingCurveAllowed(gdaCurve, true);
        router = new VeryFastRouter(pairFactory);
        pairFactory.setRouterAllowed(LSSVMRouter(payable(address(router))), true);

        // Set up hook
        bhook = new OrderBhook(pairFactory, address(this));

        // Set up royalties for the test 721
        RoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(
            address(test721), address(royaltyLookup)
        );

        // Mint ID0 #0 to caller
        IERC721Mintable(address(test721)).mint(address(this), 0);

        test721.setApprovalForAll(address(pairFactory), true);
        test721.setApprovalForAll(address(router), true);
    }

    function _setUpPairERC721ForSaleCustom(
        uint128 spotPrice,
        uint128 delta,
        LSSVMPair.PoolType poolType,
        uint256 depositAmount,
        address _propertyChecker,
        uint256[] memory nftIdsToDeposit,
        ICurve specificCurve,
        address specificHook
    ) public returns (LSSVMPair pair) {
        pair = this.setupPairWithPropertyCheckerERC721{value: modifyInputAmount(depositAmount)}(
            PairCreationParamsWithPropertyCheckerERC721({
                factory: pairFactory,
                nft: test721,
                bondingCurve: specificCurve,
                assetRecipient: payable(address(0)),
                poolType: poolType,
                delta: delta,
                fee: 0,
                spotPrice: spotPrice,
                _idList: nftIdsToDeposit,
                initialTokenBalance: depositAmount,
                routerAddress: address(0),
                propertyChecker: _propertyChecker,
                hookAddress: specificHook
            })
        );
    }

    function test_basicCreatePoolERC721_ETH() public {
        LSSVMPair pair;

        // Create initial pool, whitelist linear curve
        bhook.addCurve(address(linearCurve));
        uint256[] memory idToDeposit = new uint256[](1);
        pair = _setUpPairERC721ForSaleCustom(
            1 ether,
            0,
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit,
            linearCurve,
            address(bhook)
        );

        // Assert it has been added
        uint256 storedQuote = bhook.getBuyQuoteForPair(address(pair));
        (,,, uint256 actualQuote,,) = pair.getBuyNFTQuote(0, 1);
        assertEq(storedQuote, actualQuote);

        // Cannot manually call
        vm.expectRevert();
        bhook.afterNewPair();

        // Cannot add GDA curve
        uint256[] memory empty = new uint256[](0);
        vm.expectRevert();
        pair = _setUpPairERC721ForSaleCustom(
            1 ether,
            uint128(1e9 + 1) << 88,
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            empty,
            gdaCurve,
            address(bhook)
        );

        // Cannot add nonzero property checker
        vm.expectRevert();
        pair = _setUpPairERC721ForSaleCustom(
            1 ether,
            uint128(1e9 + 1) << 88,
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(1), // nonzero property checker
            empty,
            gdaCurve,
            address(bhook)
        );
    }

    function test_createEmptyThenDepositPoolERC721_ERC20() public {
        Test20 token = new Test20();
        uint256[] memory empty = new uint256[](0);
        uint256 quoteValue;

        // Normal pair creation with zero as hook address shld succeed
        pairFactory.createPairERC721ERC20(
            LSSVMPairFactory.CreateERC721ERC20PairParams({
                token: ERC20(address(token)),
                nft: test721,
                bondingCurve: linearCurve,
                assetRecipient: payable(address(0)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: 0,
                fee: 0,
                spotPrice: 1 ether,
                propertyChecker: address(0),
                initialNFTIDs: empty,
                initialTokenBalance: 0,
                hookAddress: address(0),
                referralAddress: address(0)
            })
        );

        // Add linear curve to whitelist
        bhook.addCurve(address(linearCurve));

        // Can add ERC721 ERC20 pool
        LSSVMPair poolERC721ERC20 = pairFactory.createPairERC721ERC20(
            LSSVMPairFactory.CreateERC721ERC20PairParams({
                token: ERC20(address(token)),
                nft: test721,
                bondingCurve: linearCurve,
                assetRecipient: payable(address(0)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: 0,
                fee: 0,
                spotPrice: 1 ether,
                propertyChecker: address(0),
                initialNFTIDs: empty,
                initialTokenBalance: 0,
                hookAddress: address(bhook),
                referralAddress: address(0)
            })
        );

        // Getting quote for pool of both types should return 0
        quoteValue = bhook.getBuyQuoteForPair(address(poolERC721ERC20));
        assertEq(quoteValue, 0);
        quoteValue = bhook.getSellQuoteForPair(address(poolERC721ERC20));
        assertEq(quoteValue, 0);

        // Depositing enough tokens in via the factory + changing spot price should register it into the heap
        token.mint(address(this), 1 ether);
        token.approve(address(pairFactory), 1000 ether);
        pairFactory.depositERC20(ERC20(address(token)), address(poolERC721ERC20), 1 ether);
        quoteValue = bhook.getSellQuoteForPair(address(poolERC721ERC20));
        assertEq(quoteValue, 1 ether);

        // Should still be zero for buy side
        quoteValue = bhook.getBuyQuoteForPair(address(poolERC721ERC20));
        assertEq(quoteValue, 0);
    }

    function test_createEmptyThenDepositPoolERC1155_ETH() public {
        Test20 token = new Test20();
        uint256[] memory empty = new uint256[](0);
        IERC1155 test1155 = IERC1155(address(new Test1155()));
        uint256 quoteValue;
        bhook.addCurve(address(linearCurve));

        // Normal pair creation with zero as hook address shld succeed
        pairFactory.createPairERC1155ETH(
            test1155,
            linearCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            0,
            0,
            1 ether,
            0,
            0,
            address(0),
            address(0)
        );

        // Create hook pool for ETH
        LSSVMPair poolERC1155ETH = pairFactory.createPairERC1155ETH(
            test1155,
            linearCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            0,
            0,
            1 ether,
            0,
            0,
            address(bhook),
            address(0)
        );

        // Should have zero quote
        bhook.getBuyQuoteForPair(address(poolERC1155ETH));
        assertEq(quoteValue, 0);
        quoteValue = bhook.getSellQuoteForPair(address(poolERC1155ETH));
        assertEq(quoteValue, 0);

        // Deposit ETH into pool, should register for sell side, expect the quote to show up
        payable(address(poolERC1155ETH)).safeTransferETH(1 ether);
        quoteValue = bhook.getSellQuoteForPair(address(poolERC1155ETH));
        assertEq(quoteValue, 1 ether);

        // Should still be zero for buy side
        quoteValue = bhook.getBuyQuoteForPair(address(poolERC1155ETH));
        assertEq(quoteValue, 0);

        // Mint some ERC1155s and deposit in
        Test1155(address(test1155)).mint(address(this), 0, 10);
        test1155.setApprovalForAll(address(pairFactory), true);
        pairFactory.depositERC1155(test1155, 0, address(poolERC1155ETH), 10);

        // Should now be 1 ETH for the buy side
        quoteValue = bhook.getBuyQuoteForPair(address(poolERC1155ETH));
        assertEq(quoteValue, 1 ether);
    }

    function test_createEmptyThenDepositPoolERC1155_ERC20() public {
        Test20 token = new Test20();
        uint256[] memory empty = new uint256[](0);
        IERC1155 test1155 = IERC1155(address(new Test1155()));
        uint256 quoteValue;
        bhook.addCurve(address(linearCurve));

        pairFactory.createPairERC1155ERC20(
            LSSVMPairFactory.CreateERC1155ERC20PairParams({
                token: ERC20(address(token)),
                nft: test1155,
                bondingCurve: linearCurve,
                assetRecipient: payable(address(0)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: 0,
                fee: 0,
                spotPrice: 1 ether,
                nftId: 0,
                initialNFTBalance: 0,
                initialTokenBalance: 0,
                hookAddress: address(0),
                referralAddress: address(0)
            })
        );

        // Cannot add ERC1155 ERC20 pool
        LSSVMPair poolERC1155ERC20 = pairFactory.createPairERC1155ERC20(
            LSSVMPairFactory.CreateERC1155ERC20PairParams({
                token: ERC20(address(token)),
                nft: test1155,
                bondingCurve: linearCurve,
                assetRecipient: payable(address(0)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: 0,
                fee: 0,
                spotPrice: 1 ether,
                nftId: 0,
                initialNFTBalance: 0,
                initialTokenBalance: 0,
                hookAddress: address(bhook),
                referralAddress: address(0)
            })
        );

        bhook.getBuyQuoteForPair(address(poolERC1155ERC20));
        assertEq(quoteValue, 0);
        quoteValue = bhook.getSellQuoteForPair(address(poolERC1155ERC20));
        assertEq(quoteValue, 0);

        // Deposit ETH into pool, should register for sell side, expect the quote to show up
        token.mint(address(this), 1 ether);
        token.approve(address(pairFactory), 1 ether);
        pairFactory.depositERC20(ERC20(address(token)), address(poolERC1155ERC20), 1 ether);
        quoteValue = bhook.getSellQuoteForPair(address(poolERC1155ERC20));
        assertEq(quoteValue, 1 ether);

        // Should still be zero for buy side
        quoteValue = bhook.getBuyQuoteForPair(address(poolERC1155ERC20));
        assertEq(quoteValue, 0);

        // Mint some ERC1155s and deposit in
        Test1155(address(test1155)).mint(address(this), 0, 10);
        test1155.setApprovalForAll(address(pairFactory), true);
        pairFactory.depositERC1155(test1155, 0, address(poolERC1155ERC20), 10);

        // Should now be 1 ETH for the buy side
        quoteValue = bhook.getBuyQuoteForPair(address(poolERC1155ERC20));
        assertEq(quoteValue, 1 ether);
    }

    function test_listWithdrawDepositBuyERC721_ETH() public {
        // Create initial pool, whitelist linear curve
        bhook.addCurve(address(linearCurve));
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSaleCustom(
            1 ether, // price of 1 ETH
            0,
            LSSVMPair.PoolType.NFT,
            0 ether,
            address(0),
            idToDeposit,
            linearCurve,
            address(bhook)
        );

        // Check that it's also synced for a heap lookup
        assertEq(bhook.getBuyQuoteForPair(address(pair)), 1 ether);
        assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), 1 ether);

        // Withdraw the NFT
        pair.withdrawERC721(test721, idToDeposit);

        // Check that it's correctly gone from heap lookup
        assertEq(bhook.getBuyQuoteForPair(address(pair)), 0);
        assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), 0);

        // Redeposit the NFT
        pairFactory.depositNFTs(test721, idToDeposit, address(pair));

        // Check that it's also synced for a heap lookup (should be back)
        assertEq(bhook.getBuyQuoteForPair(address(pair)), 1 ether);
        assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), 1 ether);

        // Swap and purchase the NFT
        pair.swapTokenForSpecificNFTs{value: 1 ether}(idToDeposit, 1 ether, address(69), false, address(0));

        // Check that it's correctly gone from heap lookup
        assertEq(bhook.getBuyQuoteForPair(address(pair)), 0);
        assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), 0);
    }

    function test_multiItemListBuy(uint8 initialNumListings) public {
        // Fuzz X items
        // list X items (with IDs from 0 to X) at price = ID
        // remove the first X/2 items
        // assert the cheapest item is X/2 + 1
        // make the next X/4 items twice as expneisve
        // assert the cheapest item is now 3X/4 + 1

        vm.assume(initialNumListings > 10);

        // Recast to be larger size to avoid overflow issues
        uint256 numListings = initialNumListings;

        bhook.addCurve(address(linearCurve));
        uint256[] memory idToDeposit = new uint256[](1);
        address[] memory pairs = new address[](numListings);

        for (uint256 i = 1; i < numListings; ++i) {
            IERC721Mintable(address(test721)).mint(address(this), i);
            idToDeposit[0] = i;
            pairs[i - 1] = address(
                _setUpPairERC721ForSaleCustom(
                    uint128(i * (1 ether)), // price of 1 ETH
                    0,
                    LSSVMPair.PoolType.NFT,
                    0 ether,
                    address(0),
                    idToDeposit,
                    linearCurve,
                    address(bhook)
                )
            );
        }

        // Assert the cheapest item is 1 ether
        assertEq(bhook.getBuyQuoteForPair(address(pairs[0])), 1 ether);
        assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), 1 ether);

        // Remove the first X/2 items, assert that the next item always becomes the cheapest
        for (uint256 i = 1; i < numListings / 2; ++i) {
            idToDeposit[0] = i;
            LSSVMPair(pairs[i - 1]).withdrawERC721(test721, idToDeposit);
            assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), (i + 1) * (1 ether));
        }

        // Make the next X/4 items more expensive, assert that the next item always becomes the cheapest
        for (uint256 i = numListings / 2; i < (3 * numListings / 4); ++i) {
            idToDeposit[0] = i;
            LSSVMPair(pairs[i - 1]).changeSpotPrice(uint128(2 * LSSVMPair(pairs[i - 1]).spotPrice()));
            assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), (i + 1) * (1 ether));
        }
    }

    function test_multiItemListSell(uint8 initialNumListings) public {
        // Fuzz X items
        // list X items (with IDs from 0 to X) at price = ID
        // remove the first X/2 items
        // assert the cheapest item is X/2 + 1
        // make the next X/4 items twice as expneisve
        // assert the cheapest item is now 3X/4 + 1

        vm.assume(initialNumListings > 10);

        // Recast to be larger size to avoid overflow issues
        uint256 numListings = initialNumListings;

        bhook.addCurve(address(linearCurve));
        uint256[] memory empty = new uint256[](0);
        address[] memory pairs = new address[](numListings);

        for (uint256 i; i < numListings; ++i) {
            vm.deal(address(this), uint128(i * (1 ether)));
            pairs[i] = address(
                _setUpPairERC721ForSaleCustom(
                    uint128(i * (1 ether)), // price of i ETH
                    0,
                    LSSVMPair.PoolType.TOKEN,
                    uint128(i * (1 ether)),
                    address(0),
                    empty,
                    linearCurve,
                    address(bhook)
                )
            );
        }

        // Assert the best sell quote is numListings - 1 ether
        assertEq(bhook.getSellQuoteForPair(address(pairs[numListings - 1])), (numListings - 1) * 1 ether);
        assertEq(bhook.getBestSellQuoteForERC721(address(test721), address(0)), (numListings - 1) * 1 ether);

        // Remove the first X/2 items, assert that the next item always becomes the cheapest
        for (uint256 i = 1; i < numListings / 2; ++i) {
            LSSVMPairETH(payable(pairs[numListings - i])).withdrawAllETH();
            assertEq(bhook.getBestSellQuoteForERC721(address(test721), address(0)), (numListings - i - 1) * (1 ether));
        }

        // Make the next X/4 items more expensive, assert that the next item always becomes the cheapest
        for (uint256 i = numListings / 2; i < (3 * numListings / 4); ++i) {
            LSSVMPair(pairs[numListings - i]).changeSpotPrice(LSSVMPair(pairs[numListings - i]).spotPrice() / 2);
            assertEq(bhook.getBestSellQuoteForERC721(address(test721), address(0)), (numListings - i - 1) * (1 ether));
        }
    }

    // List X items
    // Swap, assert the cheapest item is shown (if it stays the cheapest)
    // Swap, assert the cheapest item is the next item
    function test_multiItemSwap() public {
        LSSVMPair pair;

        // Create initial pool, whitelist linear curve
        bhook.addCurve(address(linearCurve));
        uint256[] memory idToDeposit = new uint256[](1);
        pair = _setUpPairERC721ForSaleCustom(
            1 ether,
            0,
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit,
            linearCurve,
            address(bhook)
        );

        // Mint and deposit another NFT in
        IMintable(address(test721)).mint(address(this), 1);
        idToDeposit[0] = 1;
        pairFactory.depositNFTs(test721, idToDeposit, address(pair));

        // Create a new pool and list at a higher price
        idToDeposit[0] = 2;
        IMintable(address(test721)).mint(address(this), 2);
        LSSVMPair pair2 = _setUpPairERC721ForSaleCustom(
            2 ether, 0, LSSVMPair.PoolType.TRADE, 0, address(0), idToDeposit, linearCurve, address(bhook)
        );

        idToDeposit[0] = 0;
        pair.swapTokenForSpecificNFTs{value: 1 ether}(idToDeposit, 1 ether, address(this), false, address(0));

        // Buy ID 0, assert that the lowest is 1 ETH (still) and is pair
        assertEq(bhook.getBuyQuoteForPair(address(pair)), 1 ether);
        assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), 1 ether);

        // The buy ID 1, assert that the lowest is 2 ETH  and is now pair2
        idToDeposit[0] = 1;
        pair.swapTokenForSpecificNFTs{value: 1 ether}(idToDeposit, 1 ether, address(this), false, address(0));
        assertEq(bhook.getBuyQuoteForPair(address(pair)), 0);
        assertEq(bhook.getBuyQuoteForPair(address(pair2)), 2 ether);
        assertEq(bhook.getBestBuyQuoteForERC721(address(test721), address(0)), 2 ether);
    }
}
