// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {RouterCaller} from "../mixins/RouterCaller.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

abstract contract RouterSinglePool is Test, ERC721Holder, ConfigurableWithRoyalties, RouterCaller {
    IERC721Mintable test721;
    ICurve bondingCurve;
    LSSVMPairFactory factory;
    LSSVMRouter router;
    LSSVMPair pair;
    address payable constant feeRecipient = payable(address(69));
    address payable constant tradeFeeRecipient = payable(address(420));
    uint256 constant protocolFeeMultiplier = 3e15;
    uint256 constant numInitialNFTs = 10;

    RoyaltyRegistry royaltyRegistry;

    function setUp() public {
        bondingCurve = setupCurve();
        test721 = setup721();
        royaltyRegistry = setupRoyaltyRegistry();
        factory = setupFactory(royaltyRegistry, feeRecipient);
        router = new LSSVMRouter(factory);
        factory.setBondingCurveAllowed(bondingCurve, true);
        factory.setRouterAllowed(router, true);

        // set NFT approvals
        test721.setApprovalForAll(address(factory), true);
        test721.setApprovalForAll(address(router), true);

        // Setup pair parameters
        uint128 delta = 0 ether;
        uint128 spotPrice = 1 ether;
        uint256[] memory idList = new uint256[](numInitialNFTs);
        for (uint256 i = 1; i <= numInitialNFTs; i++) {
            test721.mint(address(this), i);
            idList[i - 1] = i;
        }

        // Create a pair with a spot price of 1 eth, 10 NFTs, and no price increases
        pair = this.setupPair{value: modifyInputAmount(10 ether)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            modifyDelta(uint64(delta)),
            0,
            spotPrice,
            idList,
            10 ether,
            address(router)
        );

        // mint extra NFTs to this contract (i.e. to be held by the caller)
        for (uint256 i = numInitialNFTs + 1; i <= 2 * numInitialNFTs; i++) {
            test721.mint(address(this), i);
        }
    }

    function test_swapTokenForSingleSpecificNFT() public {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
        uint256 inputAmount;
        (,,, inputAmount,) = pair.getBuyNFTQuote(1);
        this.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            router, swapList, payable(address(this)), address(this), block.timestamp, inputAmount
        );
    }

    function test_swapTokenForSingleNFTWithFeeRecipient() public {
        // Set protocol fee to 0% to make the math easier
        factory.changeProtocolFeeMultiplier(0);

        // Set 10% fee to go to tradeFeeRecipient
        pair.changeAssetRecipient(tradeFeeRecipient);
        pair.changeFee(0.1e18);

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
        uint256 inputAmount;
        (,,, inputAmount,) = pair.getBuyNFTQuote(1);
        this.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            router, swapList, payable(address(this)), address(this), block.timestamp, inputAmount
        );

        // Do trade fee check to ensure that the recipient received the tokens
        // Which should be twice the trade fee amount, i.e. 0.2
        assertEq(getBalance(tradeFeeRecipient), 2 * inputAmount / 11);
    }

    function test_swapSingleNFTForToken() public {
        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = numInitialNFTs + 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
        router.swapNFTsForToken(swapList, outputAmount, payable(address(this)), block.timestamp);
    }

    function testGas_swapSingleNFTForToken5Times() public {
        for (uint256 i = 1; i <= 5; i++) {
            (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
            uint256[] memory nftIds = new uint256[](1);
            nftIds[0] = numInitialNFTs + i;
            LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
            swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
            router.swapNFTsForToken(swapList, outputAmount, payable(address(this)), block.timestamp);
        }
    }

    function test_swapSingleNFTForSpecificNFT() public {
        // construct NFT to token swap list
        uint256[] memory sellNFTIds = new uint256[](1);
        sellNFTIds[0] = numInitialNFTs + 1;
        LSSVMRouter.PairSwapSpecific[] memory nftToTokenSwapList = new LSSVMRouter.PairSwapSpecific[](1);
        nftToTokenSwapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: sellNFTIds});

        // construct token to NFT swap list
        uint256[] memory buyNFTIds = new uint256[](1);
        buyNFTIds[0] = 1;
        LSSVMRouter.PairSwapSpecific[] memory tokenToNFTSwapList = new LSSVMRouter.PairSwapSpecific[](1);
        tokenToNFTSwapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: buyNFTIds});

        // NOTE: We send some tokens (more than enough) to cover the protocol fee
        uint256 inputAmount = 0.01 ether;
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
    }

    function test_swapTokenforSpecific5NFTs() public {
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        uint256[] memory nftIds = new uint256[](5);
        nftIds[0] = 1;
        nftIds[1] = 2;
        nftIds[2] = 3;
        nftIds[3] = 4;
        nftIds[4] = 5;
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
        uint256 startBalance = test721.balanceOf(address(this));
        uint256 inputAmount;
        (,,, inputAmount,) = pair.getBuyNFTQuote(5);
        this.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            router, swapList, payable(address(this)), address(this), block.timestamp, inputAmount
        );
        uint256 endBalance = test721.balanceOf(address(this));
        require((endBalance - startBalance) == 5, "Too few NFTs acquired");
    }

    function test_swap5NFTsForToken() public {
        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(5);
        uint256[] memory nftIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            nftIds[i] = numInitialNFTs + i + 1;
        }
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
        router.swapNFTsForToken(swapList, outputAmount, payable(address(this)), block.timestamp);
    }

    function testFail_swapTokenForSingleSpecificNFTSlippage() public {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
        uint256 inputAmount;
        (,,, inputAmount,) = pair.getBuyNFTQuote(1);
        inputAmount = inputAmount - 1 wei;
        this.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            router, swapList, payable(address(this)), address(this), block.timestamp, inputAmount
        );
    }

    function testFail_swapSingleNFTForNonexistentToken() public {
        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = numInitialNFTs + 1;
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
        uint256 sellAmount;
        (,,, sellAmount,) = pair.getSellNFTQuote(1);
        sellAmount = sellAmount + 1 wei;
        router.swapNFTsForToken(swapList, sellAmount, payable(address(this)), block.timestamp);
    }

    function testFail_swapSingleNFTForTokenWithEmptyList() public {
        uint256[] memory nftIds = new uint256[](0);
        LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
        swapList[0] = LSSVMRouter.PairSwapSpecific({pair: pair, nftIds: nftIds});
        uint256 sellAmount;
        (,,, sellAmount,) = pair.getSellNFTQuote(1);
        sellAmount = sellAmount + 1 wei;
        router.swapNFTsForToken(swapList, sellAmount, payable(address(this)), block.timestamp);
    }
}
