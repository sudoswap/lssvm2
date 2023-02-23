// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {Test721} from "../../mocks/Test721.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {XykCurve} from "../../bonding-curves/XykCurve.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMPairCloner} from "../../lib/LSSVMPairCloner.sol";
import {LSSVMPairERC721ETH} from "../../erc721/LSSVMPairERC721ETH.sol";
import {TestRoyaltyRegistry} from "../../mocks/TestRoyaltyRegistry.sol";
import {CurveErrorCodes} from "../../bonding-curves/CurveErrorCodes.sol";
import {LSSVMPairERC1155ETH} from "../../erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "../../erc721/LSSVMPairERC721ERC20.sol";
import {LSSVMPairERC1155ERC20} from "../../erc1155/LSSVMPairERC1155ERC20.sol";

contract XykCurveTest is Test, ERC721Holder {
    using FixedPointMathLib for uint256;

    uint256 constant MIN_PRICE = 1 gwei;

    XykCurve curve;
    LSSVMPairFactory factory;
    LSSVMPair ethPair;
    Test721 nft;

    RoyaltyEngine royaltyEngine;

    receive() external payable {}

    function setUp() public {
        RoyaltyRegistry royaltyRegistry = new RoyaltyRegistry();
        royaltyRegistry.initialize();
        royaltyEngine = new RoyaltyEngine(address(royaltyRegistry));

        factory = setupFactory(payable(address(0)));
        curve = new XykCurve();
        factory.setBondingCurveAllowed(curve, true);
    }

    function setUpEthPair(uint256 numNfts, uint256 value) public {
        nft = new Test721();
        nft.setApprovalForAll(address(factory), true);
        uint256[] memory idList = new uint256[](numNfts);
        for (uint256 i = 1; i <= numNfts; i++) {
            nft.mint(address(this), i);
            idList[i - 1] = i;
        }

        ethPair = factory.createPairERC721ETH{value: value}(
            nft, curve, payable(0), LSSVMPair.PoolType.TRADE, uint128(numNfts), 0, uint128(value), address(0), idList
        );
    }

    function setUpEmptyEthPair(uint256 value) public {
        nft = new Test721();
        nft.setApprovalForAll(address(factory), true);
        uint256[] memory idList = new uint256[](0);

        ethPair = factory.createPairERC721ETH{value: value}(
            nft, curve, payable(0), LSSVMPair.PoolType.TRADE, 0, 0, uint128(value), address(0), idList
        );
    }

    function setupFactory(address payable feeRecipient) public virtual returns (LSSVMPairFactory) {
        LSSVMPairERC721ETH erc721ETHTemplate = new LSSVMPairERC721ETH(royaltyEngine);
        LSSVMPairERC721ERC20 erc721ERC20Template = new LSSVMPairERC721ERC20(royaltyEngine);
        LSSVMPairERC1155ETH erc1155ETHTemplate = new LSSVMPairERC1155ETH(royaltyEngine);
        LSSVMPairERC1155ERC20 erc1155ERC20Template = new LSSVMPairERC1155ERC20(royaltyEngine);
        return new LSSVMPairFactory(
            erc721ETHTemplate,
            erc721ERC20Template,
            erc1155ETHTemplate,
            erc1155ERC20Template,
            feeRecipient,
            0, // Zero protocol fee to make calculations easier
            address(this)
        );
    }

    function test_getBuyInfoCannotHave0NumItems() public {
        // arrange
        uint256 numItems = 0;

        // act
        (CurveErrorCodes.Error error,,,,,) = curve.getBuyInfo(0, 0, numItems, 0, 0);

        // assert
        assertEq(
            uint256(error),
            uint256(CurveErrorCodes.Error.INVALID_NUMITEMS),
            "Should have returned invalid num items error"
        );
    }

    function test_getSellInfoCannotHave0NumItems() public {
        // arrange
        uint256 numItems = 0;

        // act
        (CurveErrorCodes.Error error,,,,,) = curve.getSellInfo(0, 0, numItems, 0, 0);

        // assert
        assertEq(
            uint256(error),
            uint256(CurveErrorCodes.Error.INVALID_NUMITEMS),
            "Should have returned invalid num items error"
        );
    }

    function test_getBuyInfoReturnsNewReserves() public {
        // arrange
        uint256 numNfts = 5;
        uint256 value = 1 ether;
        setUpEthPair(numNfts, value);
        uint256 numItemsToBuy = 2;

        // act
        (CurveErrorCodes.Error error, uint256 newSpotPrice, uint256 newDelta, uint256 inputValue,) =
            ethPair.getBuyNFTQuote(numItemsToBuy);

        // assert
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Should not have errored");
        assertEq(newDelta, numNfts - numItemsToBuy, "Should have updated virtual nft reserve");
        assertEq(newSpotPrice, inputValue + value, "Should have updated virtual eth reserve");
    }

    function test_getBuyInfoOverflow() public {
        uint256 nftBalance = 10000000002;
        uint256 tokenBalance = type(uint128).max / 10000000000;
        setUpEmptyEthPair(tokenBalance);
        ethPair.changeDelta(uint128(nftBalance));
        uint256 numItemsToBuy = 10000000001;

        (CurveErrorCodes.Error error, uint256 newSpotPrice, uint256 newDelta, uint256 inputValue,) =
            ethPair.getBuyNFTQuote(numItemsToBuy);
        assertEq(
            uint256(error), uint256(CurveErrorCodes.Error.SPOT_PRICE_OVERFLOW), "Error code not SPOT_PRICE_OVERFLOW"
        );
        assertEq(newDelta, 0);
        assertEq(newSpotPrice, 0);
        assertEq(inputValue, 0);
    }

    function test_getSellInfoReturnsNewReserves() public {
        // arrange
        uint256 numNfts = 5;
        uint256 value = 1 ether;
        setUpEthPair(numNfts, value);
        uint256 numItemsToSell = 2;

        // act
        (CurveErrorCodes.Error error, uint256 newSpotPrice, uint256 newDelta, uint256 inputValue,,) =
            ethPair.getSellNFTQuote(1, numItemsToSell);

        // assert
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Should not have errored");
        assertEq(newDelta, numNfts + numItemsToSell, "Should have updated virtual nft reserve");
        assertEq(newSpotPrice, value - inputValue, "Should have updated virtual eth reserve");
    }

    function test_getBuyInfoReturnsInputValue() public {
        // arrange
        uint256 numNfts = 5;
        uint256 value = 0.8 ether;
        setUpEthPair(numNfts, value);
        uint256 numItemsToBuy = 3;
        uint256 expectedInputValue = (numItemsToBuy * value) / (numNfts - numItemsToBuy);

        // act
        (CurveErrorCodes.Error error,,, uint256 inputValue,) = ethPair.getBuyNFTQuote(numItemsToBuy);

        // assert
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Should not have errored");
        assertEq(inputValue, expectedInputValue, "Should have calculated input value");
    }

    function test_getSellInfoReturnsOutputValue() public {
        // arrange
        uint256 numNfts = 5;
        uint256 value = 0.8 ether;
        setUpEthPair(numNfts, value);
        uint256 numItemsToSell = 3;
        uint256 expectedOutputValue = (numItemsToSell * value) / (numNfts + numItemsToSell);

        // act
        (CurveErrorCodes.Error error,,, uint256 outputValue,,) = ethPair.getSellNFTQuote(1, numItemsToSell);

        // assert
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Should not have errored");
        assertEq(outputValue, expectedOutputValue, "Should have calculated output value");
    }

    function test_getBuyInfoCalculatesProtocolFee() public {
        // arrange
        uint256 numNfts = 5;
        uint256 value = 0.8 ether;
        setUpEthPair(numNfts, value);
        factory.changeProtocolFeeMultiplier((2 * 1e18) / 100); // 2%
        uint256 numItemsToBuy = 3;
        uint256 expectedProtocolFee = (2 * ((numItemsToBuy * value) / (numNfts - numItemsToBuy))) / 100;

        // act
        (CurveErrorCodes.Error error,,,, uint256 protocolFee) = ethPair.getBuyNFTQuote(numItemsToBuy);

        // assert
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Should not have errored");
        assertEq(protocolFee, expectedProtocolFee, "Should have calculated protocol fee");
    }

    function test_getSellInfoCalculatesProtocolFee() public {
        // arrange
        uint256 numNfts = 5;
        uint256 value = 0.8 ether;
        setUpEthPair(numNfts, value);
        factory.changeProtocolFeeMultiplier((2 * 1e18) / 100); // 2%
        uint256 numItemsToSell = 3;
        uint256 expectedProtocolFee = (2 * ((numItemsToSell * value) / (numNfts + numItemsToSell))) / 100;

        // act
        (CurveErrorCodes.Error error,,,, uint256 protocolFee,) = ethPair.getSellNFTQuote(1, numItemsToSell);

        // assert
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Should not have errored");
        assertEq(protocolFee, expectedProtocolFee, "Should have calculated protocol fee");
    }

    function test_getSellInfoOverflow() public {
        uint256 nftBalance = type(uint128).max;
        uint256 tokenBalance = 1 ether;
        setUpEmptyEthPair(tokenBalance);
        ethPair.changeDelta(uint128(nftBalance));
        uint256 numItemsToSell = 1;

        (CurveErrorCodes.Error error, uint256 newSpotPrice, uint256 newDelta, uint256 inputValue,,) =
            ethPair.getSellNFTQuote(1, numItemsToSell);
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.DELTA_OVERFLOW), "Error code not DELTA_OVERFLOW");
        assertEq(newDelta, 0);
        assertEq(newSpotPrice, 0);
        assertEq(inputValue, 0);
    }

    function test_swapTokenForSpecificNFTs() public {
        // arrange
        uint256 numNfts = 5;
        uint256 value = 0.8 ether;
        setUpEthPair(numNfts, value);
        uint256 numItemsToBuy = 2;
        uint256 ethBalanceBefore = address(this).balance;
        uint256 nftBalanceBefore = nft.balanceOf(address(this));

        factory.changeProtocolFeeMultiplier((2 * 1e18) / 100); // 2%
        ethPair.changeFee((1 * 1e18) / 100); // 1%

        (CurveErrorCodes.Error error,,, uint256 inputValue,) = ethPair.getBuyNFTQuote(numItemsToBuy);

        // act
        uint256[] memory idList = new uint256[](numItemsToBuy);
        for (uint256 i = 1; i <= numItemsToBuy; i++) {
            idList[i - 1] = i;
        }
        uint256 inputAmount =
            ethPair.swapTokenForSpecificNFTs{value: inputValue}(idList, inputValue, address(this), false, address(0));

        // assert
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Should not have errored");
        assertEq(ethBalanceBefore - address(this).balance, inputValue, "Should have transferred ETH");
        assertEq(nft.balanceOf(address(this)) - nftBalanceBefore, numItemsToBuy, "Should have received NFTs");

        uint256 withoutFeeInputAmount = (inputAmount * 1e18) / 103e16;
        assertEq(
            ethPair.spotPrice(),
            uint128(address(ethPair).balance) - (withoutFeeInputAmount * 1e16) / 1e18,
            "Spot price should match eth balance - fee after swap"
        );
        assertEq(ethPair.delta(), nft.balanceOf(address(ethPair)), "Delta should match nft balance after swap");
    }

    function test_swapNFTsForToken() public {
        // arrange
        uint256 numNfts = 5;
        uint256 value = 0.8 ether;
        setUpEthPair(numNfts, value);

        factory.changeProtocolFeeMultiplier((2 * 1e18) / 100); // 2%
        ethPair.changeFee((1 * 1e18) / 100); // 1%

        uint256 numItemsToSell = 2;
        (CurveErrorCodes.Error error,,, uint256 outputValue,,) = ethPair.getSellNFTQuote(1, numItemsToSell);

        uint256[] memory idList = new uint256[](numItemsToSell);
        for (uint256 i = 1; i <= numItemsToSell; i++) {
            nft.mint(address(this), numNfts + i);
            idList[i - 1] = numNfts + i;
        }

        uint256 ethBalanceBefore = address(this).balance;
        uint256 nftBalanceBefore = nft.balanceOf(address(this));
        nft.setApprovalForAll(address(ethPair), true);

        // act
        uint256 outputAmount = ethPair.swapNFTsForToken(idList, outputValue, payable(address(this)), false, address(0));

        // assert
        assertEq(uint256(error), uint256(CurveErrorCodes.Error.OK), "Should not have errored");
        assertEq(address(this).balance - ethBalanceBefore, outputValue, "Should have received ETH");
        assertEq(nftBalanceBefore - nft.balanceOf(address(this)), numItemsToSell, "Should have sent NFTs");

        uint256 withoutFeeOutputAmount = (outputAmount * 1e18) / 0.97e18;
        assertEq(
            ethPair.spotPrice(),
            uint128(address(ethPair).balance) - ((withoutFeeOutputAmount * 1e16) / 1e18),
            "Spot price + fee should match eth balance after swap"
        );
        assertEq(ethPair.delta(), nft.balanceOf(address(ethPair)), "Delta should match nft balance after swap");
    }
}
