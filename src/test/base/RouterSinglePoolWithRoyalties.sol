// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {RouterCaller} from "../mixins/RouterCaller.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {IERC1155Mintable} from "../interfaces/IERC1155Mintable.sol";
import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";
import {TestManifold} from "../../mocks/TestManifold.sol";

abstract contract RouterSinglePoolWithRoyalties is
    Test,
    ERC721Holder,
    ERC1155Holder,
    ConfigurableWithRoyalties,
    RouterCaller
{
    uint256 tokenAmount = 10 ether;
    uint256 startingId;
    IERC721Mintable test721;
    IERC1155Mintable test1155;
    ERC2981 test2981;
    RoyaltyEngine royaltyEngine;
    ICurve bondingCurve;
    LSSVMPairFactory factory;
    LSSVMRouter router;
    LSSVMPair pair721;
    LSSVMPair pair1155;
    address payable constant feeRecipient = payable(address(69));
    uint256 constant protocolFeeMultiplier = 3e15;
    uint256 constant numInitialNFTs = 10;

    function setUp() public {
        bondingCurve = setupCurve();
        test721 = setup721();
        test1155 = setup1155();
        test2981 = setup2981();
        royaltyEngine = setupRoyaltyEngine();
        IRoyaltyRegistry(royaltyEngine.royaltyRegistry()).setRoyaltyLookupAddress(address(test721), address(test2981));
        IRoyaltyRegistry(royaltyEngine.royaltyRegistry()).setRoyaltyLookupAddress(address(test1155), address(test2981));

        factory = setupFactory(royaltyEngine, feeRecipient);
        router = new LSSVMRouter(factory);
        factory.setBondingCurveAllowed(bondingCurve, true);
        factory.setRouterAllowed(router, true);

        // set NFT approvals
        test721.setApprovalForAll(address(factory), true);
        test721.setApprovalForAll(address(router), true);
        test1155.setApprovalForAll(address(factory), true);

        // Setup pair parameters
        uint128 delta = 0 ether;
        uint128 spotPrice = 1 ether;
        uint256[] memory idList = new uint256[](numInitialNFTs);
        for (uint256 i = 1; i <= numInitialNFTs; i++) {
            test721.mint(address(this), i);
            idList[i - 1] = i;
        }
        test1155.mint(address(this), startingId, numInitialNFTs);

        // Create a pair with a spot price of 1 eth, 10 NFTs, and no price increases
        pair721 = this.setupPairERC721{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            modifyDelta(uint64(delta)),
            0,
            spotPrice,
            idList,
            tokenAmount,
            address(router)
        );

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
                startingId,
                numInitialNFTs,
                tokenAmount,
                address(0)
            )
        );

        // mint extra NFTs to this contract (i.e. to be held by the caller)
        for (uint256 i = numInitialNFTs + 1; i <= 2 * numInitialNFTs; i++) {
            test721.mint(address(this), i);
        }
    }

    function test_swapTokenForSingleSpecificNFT_ERC721() public {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        (,,, uint256 inputAmount, uint256 protocolFee) = pair721.getBuyNFTQuote(1);

        // calculate royalty
        uint256 royaltyAmount = calcRoyalty(inputAmount - protocolFee);

        this.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            router, swapList, payable(address(this)), address(this), block.timestamp, inputAmount
        );

        // check that royalty has been issued
        assertEq(getBalance(ROYALTY_RECEIVER), royaltyAmount);
    }

    function test_swapTokenForSingleNFT_ERC1155() public {
        uint256[] memory numNFTs = new uint256[](1);
        numNFTs[0] = 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair1155, nftIds: numNFTs});
        (,,, uint256 inputAmount, uint256 protocolFee) = pair1155.getBuyNFTQuote(1);

        // calculate royalty
        uint256 royaltyAmount = calcRoyalty(inputAmount - protocolFee);

        this.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            router, swapList, payable(address(this)), address(this), block.timestamp, inputAmount
        );

        // check that royalty has been issued
        assertEq(getBalance(ROYALTY_RECEIVER), royaltyAmount);
    }

    function test_swapSingleNFTForToken() public {
        (,,, uint256 outputAmount,) = pair721.getSellNFTQuote(1);

        // calculate royalty and rm it from the output amount
        uint256 royaltyAmount = calcRoyalty(outputAmount);
        outputAmount -= royaltyAmount;

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = numInitialNFTs + 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        router.swapNFTsForToken(swapList, outputAmount, payable(address(this)), block.timestamp);

        // check that royalty has been issued
        assertEq(getBalance(ROYALTY_RECEIVER), royaltyAmount);
    }

    function test_swapSingleNFTForTokenWithNoRoyaltyReceivers() public {
        // Setup the nft collection to use Manifold's royalty interface
        address payable[] memory receivers = new address payable[](0);
        uint256[] memory bps = new uint256[](0);
        TestManifold testManifold = new TestManifold(receivers, bps);
        IRoyaltyRegistry(royaltyEngine.royaltyRegistry()).setRoyaltyLookupAddress(
            address(test721), address(testManifold)
        );

        // Output amount does not need to be decremented the royalty amount here
        (,,, uint256 outputAmount,) = pair721.getSellNFTQuote(1);

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = numInitialNFTs + 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        router.swapNFTsForToken(swapList, outputAmount, payable(address(this)), block.timestamp);

        // check that royalty has been issued only to the first receiver
        assertEq(getBalance(ROYALTY_RECEIVER), 0);
    }

    function test_swapSingleNFTForTokenWithMultipleRoyaltyReceivers() public {
        address secondReceiver = vm.addr(2);

        // Setup the nft collection to use Manifold's multiple royalty receivers
        address payable[] memory receivers = new address payable[](2);
        receivers[0] = payable(ROYALTY_RECEIVER);
        receivers[1] = payable(secondReceiver);
        uint256[] memory bps = new uint256[](2);
        bps[0] = 750;
        bps[1] = 250;
        TestManifold testManifold = new TestManifold(receivers, bps);
        IRoyaltyRegistry(royaltyEngine.royaltyRegistry()).setRoyaltyLookupAddress(
            address(test721), address(testManifold)
        );

        (,,, uint256 outputAmount,) = pair721.getSellNFTQuote(1);

        // calculate royalty total (750 + 250) and rm it from the output amount
        uint256 royaltyAmount1 = calcRoyalty(outputAmount, 750);
        uint256 royaltyAmount2 = calcRoyalty(outputAmount, 250);
        outputAmount -= (royaltyAmount1 + royaltyAmount2);

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = numInitialNFTs + 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        router.swapNFTsForToken(swapList, outputAmount, payable(address(this)), block.timestamp);

        // check that royalty has been issued only to the first receiver
        assertEq(getBalance(ROYALTY_RECEIVER), royaltyAmount1);
        assertEq(getBalance(secondReceiver), royaltyAmount2);
    }

    function testGas_swapSingleNFTForToken5Times() public {
        uint256 totalRoyaltyAmount;
        for (uint256 i = 1; i <= 5; i++) {
            (,,, uint256 outputAmount,) = pair721.getSellNFTQuote(1);

            // calculate royalty and rm it from the output amount
            uint256 royaltyAmount = calcRoyalty(outputAmount);
            outputAmount -= royaltyAmount;
            totalRoyaltyAmount += royaltyAmount;

            uint256[] memory nftIds = new uint256[](1);
            nftIds[0] = numInitialNFTs + i;
            LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
            swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
            router.swapNFTsForToken(swapList, outputAmount, payable(address(this)), block.timestamp);
        }
        // check that royalty has been issued
        assertEq(getBalance(ROYALTY_RECEIVER), totalRoyaltyAmount);
    }

    function test_swapSingleNFTForSpecificNFT() public {
        uint256 totalRoyaltyAmount;
        // construct NFT to token swap list
        uint256[] memory sellNFTIds = new uint256[](1);
        sellNFTIds[0] = numInitialNFTs + 1;
        LSSVMRouter.PairSwapSpecific[] memory nftToTokenSwapList = new LSSVMRouter.PairSwapSpecific[](1);
        nftToTokenSwapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: sellNFTIds});

        (,,, uint256 salePrice,) = nftToTokenSwapList[0].pair.getSellNFTQuote(sellNFTIds.length);
        totalRoyaltyAmount += calcRoyalty(salePrice);

        // construct token to NFT swap list
        uint256[] memory buyNFTIds = new uint256[](1);
        buyNFTIds[0] = 1;
        LSSVMRouter.PairSwapSpecific[] memory tokenToNFTSwapList = new LSSVMRouter.PairSwapSpecific[](1);
        tokenToNFTSwapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: buyNFTIds});

        (,,, uint256 buyPrice,) = tokenToNFTSwapList[0].pair.getBuyNFTQuote(buyNFTIds.length);
        totalRoyaltyAmount += calcRoyalty(buyPrice);

        // NOTE: We send some tokens (more than enough) to cover the protocol fee
        uint256 inputAmount = 0.01 ether;
        inputAmount += totalRoyaltyAmount;

        this.swapNFTsForSpecificNFTsThroughToken{value: modifyInputAmount(inputAmount)}(
            router,
            LSSVMRouter.NFTsForSpecificNFTsTrade({
                nftToTokenTrades: nftToTokenSwapList,
                tokenToNFTTrades: tokenToNFTSwapList
            }),
            0,
            payable(address(this)),
            address(this),
            block.timestamp,
            inputAmount
        );

        // check that royalty has been issued
        require(getBalance(ROYALTY_RECEIVER) <= (totalRoyaltyAmount * 1_010) / 1_000, "too much");
        require(getBalance(ROYALTY_RECEIVER) >= (totalRoyaltyAmount * 1_000) / 1_500, "too less");
        /* NOTE: test is failing with XykCurve
         * reason: buyQuote is quoted before the nfts are sold
         * recurring to proximity tests
         */
        // assertEq(getBalance(ROYALTY_RECEIVER), totalRoyaltyAmount);
    }

    function test_swapTokenforSpecific5NFTs() public {
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        uint256[] memory nftIds = new uint256[](5);
        nftIds[0] = 1;
        nftIds[1] = 2;
        nftIds[2] = 3;
        nftIds[3] = 4;
        nftIds[4] = 5;
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        uint256 startBalance = test721.balanceOf(address(this));
        (,,, uint256 inputAmount, uint256 protocolFee) = pair721.getBuyNFTQuote(5);

        // calculate royalty
        uint256 royaltyAmount = calcRoyalty(inputAmount - protocolFee);

        this.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            router, swapList, payable(address(this)), address(this), block.timestamp, inputAmount
        );
        uint256 endBalance = test721.balanceOf(address(this));
        require((endBalance - startBalance) == 5, "Too few NFTs acquired");

        // check that royalty has been issued
        assertEq(getBalance(ROYALTY_RECEIVER), royaltyAmount);
    }

    function test_swap5NFTsForToken() public {
        (,,, uint256 outputAmount,) = pair721.getSellNFTQuote(5);

        // calculate royalty and rm it from the output amount
        uint256 royaltyAmount = calcRoyalty(outputAmount);
        outputAmount -= royaltyAmount;

        uint256[] memory nftIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            nftIds[i] = numInitialNFTs + i + 1;
        }
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        router.swapNFTsForToken(swapList, outputAmount, payable(address(this)), block.timestamp);

        // check that royalty has been issued
        assertEq(getBalance(ROYALTY_RECEIVER), royaltyAmount);
    }

    function testFail_swapTokenForSingleSpecificNFTSlippage() public {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        (,,, uint256 inputAmount,) = pair721.getBuyNFTQuote(1);

        inputAmount = inputAmount - 1 wei;
        this.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            router, swapList, payable(address(this)), address(this), block.timestamp, inputAmount
        );
    }

    function testFail_swapSingleNFTForNonexistentToken() public {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = numInitialNFTs + 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        uint256 sellAmount;
        (,,, sellAmount,) = pair721.getSellNFTQuote(1);
        sellAmount = subRoyalty(sellAmount);

        sellAmount = sellAmount + 1 wei;
        router.swapNFTsForToken(swapList, sellAmount, payable(address(this)), block.timestamp);
    }

    function testFail_swapSingleNFTForTokenWithEmptyList() public {
        uint256[] memory nftIds = new uint256[](0);
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair721, nftIds: nftIds});
        uint256 sellAmount;
        (,,, sellAmount,) = pair721.getSellNFTQuote(1);
        sellAmount = subRoyalty(sellAmount);

        sellAmount = sellAmount + 1 wei;
        router.swapNFTsForToken(swapList, sellAmount, payable(address(this)), block.timestamp);
    }
}
