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
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMPairERC721} from "../../erc721/LSSVMPairERC721.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {ILSSVMPairFactoryLike} from "../../ILSSVMPairFactoryLike.sol";
import {IPropertyChecker} from "../../property-checking/IPropertyChecker.sol";
import {MerklePropertyChecker} from "../../property-checking/MerklePropertyChecker.sol";
import {RangePropertyChecker} from "../../property-checking/RangePropertyChecker.sol";
import {PropertyCheckerFactory} from "../../property-checking/PropertyCheckerFactory.sol";

import {Test20} from "../../mocks/Test20.sol";
import {Test721} from "../../mocks/Test721.sol";

abstract contract PropertyChecking is Test, ERC721Holder, ConfigurableWithRoyalties {
    uint128 delta = 1.1 ether;
    uint128 spotPrice = 20 ether;
    uint256 tokenAmount = 100 ether;
    uint256 numItems = 10;
    uint256[] emptyList;
    ERC2981 test2981;
    IERC721 test721;
    IERC721 test721Other;
    ERC20 testERC20;
    ICurve bondingCurve;
    LSSVMPairFactory factory;
    address payable constant feeRecipient = payable(address(69));
    RoyaltyEngine royaltyEngine;
    PropertyCheckerFactory propertyCheckerFactory;

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
        }

        MerklePropertyChecker checker1 = new MerklePropertyChecker();
        RangePropertyChecker checker2 = new RangePropertyChecker();
        propertyCheckerFactory = new PropertyCheckerFactory(checker1, checker2);
    }

    // Tests that swapping for an item if the pair has properties set will fail if property data is not passed in
    function test_normalSwapFailsIfPropertyCheckerSet() public {
        RangePropertyChecker checker = propertyCheckerFactory.createRangePropertyChecker(0, 0);

        // Deploy a pair with the property checker set
        PairCreationParamsWithPropertyChecker memory params = PairCreationParamsWithPropertyChecker({
            factory: factory,
            nft: test721,
            bondingCurve: bondingCurve,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: delta,
            fee: 0,
            spotPrice: spotPrice,
            _idList: emptyList,
            initialTokenBalance: tokenAmount,
            routerAddress: address(0),
            propertyChecker: address(checker)
        });

        LSSVMPairERC721 pair = this.setupPairWithPropertyChecker{value: this.modifyInputAmount(tokenAmount)}(params);

        // Attempt to perform a sell for item #1
        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
        uint256[] memory specificIdToSell = new uint256[](1);
        specificIdToSell[0] = 1;

        vm.expectRevert("Verify property");

        pair.swapNFTsForToken(specificIdToSell, outputAmount, payable(address(this)), false, address(this));

        // Should fail because we haven't specified the property data
    }

    // RangePropertyChecker
    // Tests that swapping for an item if the pair has properties set will fail if property is not fulfilled
    function test_propertySwapFailsIfOutOfRange() public {
        RangePropertyChecker checker = propertyCheckerFactory.createRangePropertyChecker(0, 0);

        // Deploy a pair with the property checker set
        PairCreationParamsWithPropertyChecker memory params = PairCreationParamsWithPropertyChecker({
            factory: factory,
            nft: test721,
            bondingCurve: bondingCurve,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: delta,
            fee: 0,
            spotPrice: spotPrice,
            _idList: emptyList,
            initialTokenBalance: tokenAmount,
            routerAddress: address(0),
            propertyChecker: address(checker)
        });

        LSSVMPairERC721 pair = this.setupPairWithPropertyChecker{value: this.modifyInputAmount(tokenAmount)}(params);

        // Mint any extra tokens as needed
        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair), 100 ether);
        test721.setApprovalForAll(address(pair), true);
        testERC20.approve(address(pair), 10000 ether);

        // Attempt to perform a sell for item #1
        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
        uint256[] memory specificIdToSell = new uint256[](1);
        specificIdToSell[0] = 1;

        vm.expectRevert("Property check failed");

        pair.swapNFTsForToken(
            specificIdToSell,
            outputAmount,
            payable(address(this)),
            false,
            address(this),
            "" // No extra params needed
        );
    }

    // RangePropertyChecker
    // Tests that if some tokenIds fall out of range, the entire swap will fail
    function test_propertySwapPartialFailure() public {
        RangePropertyChecker checker = propertyCheckerFactory.createRangePropertyChecker(0, 10);

        // Deploy a pair with the property checker set
        PairCreationParamsWithPropertyChecker memory params = PairCreationParamsWithPropertyChecker({
            factory: factory,
            nft: test721,
            bondingCurve: bondingCurve,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: delta,
            fee: 0,
            spotPrice: spotPrice,
            _idList: emptyList,
            initialTokenBalance: tokenAmount,
            routerAddress: address(0),
            propertyChecker: address(checker)
        });

        LSSVMPairERC721 pair = this.setupPairWithPropertyChecker{value: this.modifyInputAmount(tokenAmount)}(params);

        // Mint any extra tokens as needed
        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair), 100 ether);
        test721.setApprovalForAll(address(pair), true);
        testERC20.approve(address(pair), 10000 ether);

        // Attempt to perform a sell for item #1
        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 10;
        tokenIds[2] = 11; // This tokenId falls out of the range

        vm.expectRevert("Property check failed");

        pair.swapNFTsForToken(
            tokenIds,
            outputAmount,
            payable(address(this)),
            false,
            address(this),
            "" // No extra params needed
        );
    }

    // Tests that swapping for an item if the pair has properties set will succeed if property is fulfilled
    function test_propertySwapSucceedsIfInRange() public {
        RangePropertyChecker checker = propertyCheckerFactory.createRangePropertyChecker(0, 10);

        // Deploy a pair with the property checker set
        PairCreationParamsWithPropertyChecker memory params = PairCreationParamsWithPropertyChecker({
            factory: factory,
            nft: test721,
            bondingCurve: bondingCurve,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: delta,
            fee: 0,
            spotPrice: spotPrice,
            _idList: emptyList,
            initialTokenBalance: tokenAmount,
            routerAddress: address(0),
            propertyChecker: address(checker)
        });

        LSSVMPairERC721 pair = this.setupPairWithPropertyChecker{value: this.modifyInputAmount(tokenAmount)}(params);

        // Mint any extra tokens as needed
        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair), 100 ether);
        test721.setApprovalForAll(address(pair), true);
        testERC20.approve(address(pair), 10000 ether);

        // Perform a sell for item #1
        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 10;
        pair.swapNFTsForToken(
            tokenIds,
            outputAmount,
            payable(address(this)),
            false,
            address(this),
            "" // No extra params needed
        );
    }

    // Tests swapping behavior when a single tokenId is passsed into the merkle property checker
    function test_merklePropertyCheckerSingleId() public {
        // Create merkle tree
        uint256[2] memory tokenIds = [uint256(1), uint256(2)];
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = keccak256(abi.encodePacked(tokenIds[0]));
        hashes[1] = keccak256(abi.encodePacked(tokenIds[1]));
        hashes[2] = keccak256(abi.encodePacked(hashes[1], hashes[0]));

        // Create encoded merkle proof list
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = hashes[1];
        bytes memory proofEncoded = abi.encode(proof);
        bytes[] memory proofList = new bytes[](1);
        proofList[0] = proofEncoded;
        bytes memory proofListEncoded = abi.encode(proofList);

        MerklePropertyChecker checker = propertyCheckerFactory.createMerklePropertyChecker(hashes[2]);

        // Deploy a pair with the property checker set
        PairCreationParamsWithPropertyChecker memory params = PairCreationParamsWithPropertyChecker({
            factory: factory,
            nft: test721,
            bondingCurve: bondingCurve,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: delta,
            fee: 0,
            spotPrice: spotPrice,
            _idList: emptyList,
            initialTokenBalance: tokenAmount,
            routerAddress: address(0),
            propertyChecker: address(checker)
        });

        LSSVMPairERC721 pair = this.setupPairWithPropertyChecker{value: this.modifyInputAmount(tokenAmount)}(params);

        // Mint any extra tokens as needed
        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair), 100 ether);
        test721.setApprovalForAll(address(pair), true);
        testERC20.approve(address(pair), 10000 ether);

        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
        uint256[] memory specificIdToSell = new uint256[](1);

        // A sell for 3 will fail
        specificIdToSell[0] = 3;
        vm.expectRevert("Property check failed");
        pair.swapNFTsForToken(
            specificIdToSell, outputAmount, payable(address(this)), false, address(this), proofListEncoded
        );

        // A sell for id 1 will succeed
        specificIdToSell[0] = 1;
        pair.swapNFTsForToken(
            specificIdToSell, outputAmount, payable(address(this)), false, address(this), proofListEncoded
        );
    }

    // Tests swapping behavior when multiple tokenIds are passed into the merkle property checker
    function test_merklePropertyCheckerMultipleIds() public {
        // Create merkle tree
        uint256[2] memory tokenIds = [uint256(1), uint256(2)];
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = keccak256(abi.encodePacked(tokenIds[0]));
        hashes[1] = keccak256(abi.encodePacked(tokenIds[1]));
        hashes[2] = keccak256(abi.encodePacked(hashes[1], hashes[0]));

        MerklePropertyChecker checker = propertyCheckerFactory.createMerklePropertyChecker(hashes[2]);

        // Deploy a pair with the property checker set
        PairCreationParamsWithPropertyChecker memory params = PairCreationParamsWithPropertyChecker({
            factory: factory,
            nft: test721,
            bondingCurve: bondingCurve,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: delta,
            fee: 0,
            spotPrice: spotPrice,
            _idList: emptyList,
            initialTokenBalance: tokenAmount,
            routerAddress: address(0),
            propertyChecker: address(checker)
        });

        LSSVMPairERC721 pair = this.setupPairWithPropertyChecker{value: this.modifyInputAmount(tokenAmount)}(params);

        // Mint any extra tokens as needed
        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair), 100 ether);
        test721.setApprovalForAll(address(pair), true);
        testERC20.approve(address(pair), 10000 ether);

        (,,, uint256 outputAmount,) = pair.getSellNFTQuote(1);
        uint256[] memory idsToSell = new uint256[](2);

        // Create encoded proof list
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = hashes[1];
        bytes memory proof1Encoded = abi.encode(proof1);

        // Create encoded merkle proof list
        bytes[] memory proofList = new bytes[](2);
        proofList[0] = proof1Encoded;
        proofList[1] = proof1Encoded; // Use dummy value here

        // A sell for [1,3] will fail because 3 is not part of the merkle tree
        idsToSell[0] = 1;
        idsToSell[1] = 3;
        vm.expectRevert("Property check failed");
        pair.swapNFTsForToken(
            idsToSell, outputAmount, payable(address(this)), false, address(this), abi.encode(proofList)
        );

        // Create second proof and add it to the proof list
        bytes32[] memory proof2 = new bytes32[](1);
        proof2[0] = hashes[0];
        bytes memory proof2Encoded = abi.encode(proof2);
        proofList[1] = proof2Encoded;

        // A sell for ids [1,2] will succeed because both ids are part of the merkle tree
        idsToSell[1] = 2;
        pair.swapNFTsForToken(
            idsToSell, outputAmount, payable(address(this)), false, address(this), abi.encode(proofList)
        );
    }
}
