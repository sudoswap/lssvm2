// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Test721} from "../../mocks/Test721.sol";
import {Test1155} from "../../mocks/Test1155.sol";
import {Test20} from "../../mocks/Test20.sol";
import {MockDex} from "../../mocks/MockDex.sol";

import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LinearCurve} from "../../bonding-curves/LinearCurve.sol";

import {IMintable} from "../interfaces/IMintable.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {IERC1155Mintable} from "../interfaces/IERC1155Mintable.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {ILSSVMPair} from "../../ILSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {VeryFastRouter} from "../../VeryFastRouter.sol";
import {ZeroExRouter} from "../../ZeroExRouter.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMPairERC721ETH} from "../../erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC1155ETH} from "../../erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "../../erc721/LSSVMPairERC721ERC20.sol";
import {LSSVMPairERC1155ERC20} from "../../erc1155/LSSVMPairERC1155ERC20.sol";

import {RBF} from "../../RBF.sol";

contract RBFTest is Test, ERC1155Holder {
    ICurve bondingCurve;
    LSSVMPairFactory pairFactory;
    IERC721 test721;
    IERC1155 test1155;
    ERC20 test20;
    LSSVMPair pair721ERC20;
    LSSVMPair pair1155ERC20;
    LSSVMPair pair721ETH;
    LSSVMPair pair1155ETH;
    RBF rbf;

    function setUp() public {
        test721 = new Test721();
        test1155 = new Test1155();
        test20 = new Test20();

        RoyaltyRegistry royaltyRegistry = new RoyaltyRegistry(address(0));
        royaltyRegistry.initialize(address(this));
        RoyaltyEngine royaltyEngine = new RoyaltyEngine(
            address(royaltyRegistry)
        );

        LSSVMPairERC721ETH erc721ETHTemplate = new LSSVMPairERC721ETH(
            royaltyEngine
        );
        LSSVMPairERC721ERC20 erc721ERC20Template = new LSSVMPairERC721ERC20(
            royaltyEngine
        );
        LSSVMPairERC1155ETH erc1155ETHTemplate = new LSSVMPairERC1155ETH(
            royaltyEngine
        );
        LSSVMPairERC1155ERC20 erc1155ERC20Template = new LSSVMPairERC1155ERC20(
            royaltyEngine
        );
        pairFactory = new LSSVMPairFactory(
            erc721ETHTemplate,
            erc721ERC20Template,
            erc1155ETHTemplate,
            erc1155ERC20Template,
            payable(address(0)),
            0,
            address(this)
        );

        // Approve bonding curve
        bondingCurve = new LinearCurve();
        pairFactory.setBondingCurveAllowed(bondingCurve, true);

        // Approve NFTs for factory
        test721.setApprovalForAll(address(pairFactory), true);
        test1155.setApprovalForAll(address(pairFactory), true);
        test20.approve(address(pairFactory), 100 ether);

        // Initialize mint of tokens
        IMintable(address(test20)).mint(address(this), 100 ether);
        IERC721Mintable(address(test721)).mint(address(this), 0);
        IERC721Mintable(address(test721)).mint(address(this), 1);
        IERC721Mintable(address(test721)).mint(address(this), 2);
        IERC721Mintable(address(test721)).mint(address(this), 3);
        IERC1155Mintable(address(test1155)).mint(address(this), 0, 10);

        uint256[] memory ids = new uint256[](4);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;
        ids[3] = 3;

        rbf = new RBF(pairFactory);
        pair721ETH = pairFactory.createPairERC721ETH(
            test721, bondingCurve, payable(address(this)), LSSVMPair.PoolType.TRADE, 0, 0, 1 ether, address(0), ids
        );
    }

    function test_enterRBF() public {
        // Non pairs cannot enter
        vm.expectRevert("Invalid pair");
        rbf.onOwnershipTransferred(address(0), "");

        // Non ERC721-ETH pairs cannot enter
        pair1155ERC20 = pairFactory.createPairERC1155ERC20(
            LSSVMPairFactory.CreateERC1155ERC20PairParams({
                token: test20,
                nft: test1155,
                bondingCurve: bondingCurve,
                assetRecipient: payable(address(this)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: 0,
                fee: 0,
                spotPrice: 1 ether,
                nftId: 0,
                initialNFTBalance: 5,
                initialTokenBalance: 10 ether
            })
        );
        pair1155ETH = pairFactory.createPairERC1155ETH(
            test1155, bondingCurve, payable(address(this)), LSSVMPair.PoolType.TRADE, 0, 0, 0, 0, 0
        );
        uint256[] memory empty = new uint256[](0);
        pair721ERC20 = pairFactory.createPairERC721ERC20(
            LSSVMPairFactory.CreateERC721ERC20PairParams({
                token: test20,
                nft: test721,
                bondingCurve: bondingCurve,
                assetRecipient: payable(address(this)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: 0,
                fee: 0,
                spotPrice: 1 ether,
                propertyChecker: address(0),
                initialNFTIDs: empty,
                initialTokenBalance: 10 ether
            })
        );
        vm.expectRevert("Invalid pair type");
        pair721ERC20.transferOwnership(address(rbf), "");
        vm.expectRevert("Invalid pair type");
        pair1155ERC20.transferOwnership(address(rbf), "");
        vm.expectRevert("Invalid pair type");
        pair1155ETH.transferOwnership(address(rbf), "");

        // ERC721-ETH pair can enter
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 2, 3));

        // Verify the values are as expected
        (,, uint256 minPrice, uint256 delay, uint256 amount) = rbf.pairData(address(pair721ETH));
        assertEq(minPrice, 1);
        assertEq(delay, 2);
        assertEq(amount, 3);
    }

    function test_leaveRBF() public {
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 0, 0));

        // Fails if not owner
        vm.prank(address(1));
        address[] memory pairList = new address[](1);
        pairList[0] = address(pair721ETH);
        vm.expectRevert("Not owner");
        rbf.reclaimPairs(pairList);

        // Fails for reclaiming a pair that's not enrolled
        pairList[0] = address(pair1155ETH);
        vm.expectRevert("Not owner");
        rbf.reclaimPairs(pairList);

        pairList[0] = address(pair721ETH);
        rbf.reclaimPairs(pairList);
        assertEq(pair721ETH.owner(), address(this));
    }

    function test_borrowNoETH() public {
        // Init RBF
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 1));
        uint256[] memory idsToBorrow = new uint256[](1);
        idsToBorrow[0] = 0;

        // Skip ahead a bit so the first borrow doesn't fail
        vm.warp(1000);

        // Fails if not enough ETH is sent
        vm.expectRevert("Insufficient ETH");
        rbf.borrow(address(pair721ETH), idsToBorrow, address(0), 0);
    }

    function test_borrowTooMany() public {

        // Init RBF
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 1));
        uint256[] memory idsToBorrow;

        // Skip ahead a bit so the first borrow doesn't fail
        vm.warp(1000);

        // Fails if too many are borrowed
        idsToBorrow = new uint256[](2);
        idsToBorrow[0] = 0;
        idsToBorrow[1] = 1;
        vm.expectRevert("Too many");
        rbf.borrow{value: 10 ether}(address(pair721ETH), idsToBorrow, address(0), 0);
    }

    function test_borrowCorrectly() public {
        // Init RBF
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 1));
        uint256[] memory idsToBorrow;

        // Skip ahead a bit so the first borrow doesn't fail
        vm.warp(1000);

        idsToBorrow = new uint256[](1);
        idsToBorrow[0] = 0;
        rbf.borrow{value: 1.1 ether}(address(pair721ETH), idsToBorrow, address(0), 0);
        assertEq(test721.ownerOf(0), address(this));

        // Attempt to borrow again
        idsToBorrow = new uint256[](1);
        idsToBorrow[0] = 1;
        vm.expectRevert("Outstanding loan");
        rbf.borrow{value: 1.1 ether}(address(pair721ETH), idsToBorrow, address(0), 0);

        // Attempt to borrow from a different address
        vm.deal(address(123), 10 ether);
        idsToBorrow = new uint256[](1);
        idsToBorrow[0] = 1;
        vm.prank(address(123));
        vm.expectRevert("Too soon");
        rbf.borrow{value: 1.1 ether}(address(pair721ETH), idsToBorrow, address(0), 0);

        // Wait some more time, then borrow ID 1 successfully
        vm.warp(1011);
        vm.prank(address(123));
        rbf.borrow{value: 1.1 ether}(address(pair721ETH), idsToBorrow, address(0), 0);
        assertEq(test721.ownerOf(1), address(123));

        // Reset the pair with a higher reserve price
        address[] memory pairList = new address[](1);
        pairList[0] = address(pair721ETH);
        rbf.reclaimPairs(pairList);
        pair721ETH.transferOwnership(address(rbf), abi.encode(200, 1, 1));
        vm.expectRevert("Insufficient ETH");
        vm.deal(address(456), 10 ether);
        vm.prank(address(456));
        idsToBorrow[0] = 2;
        rbf.borrow{value: 1.1 ether}(address(pair721ETH), idsToBorrow, address(0), 0);

        // Borrow with the correct amount of ETH
        vm.prank(address(456));
        rbf.borrow{value: 2.2 ether}(address(pair721ETH), idsToBorrow, address(0), 0);
    }

    function test_borrowMultiple() public {
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 3));
        uint256[] memory idsToBorrow = new uint256[](3);
        idsToBorrow[0] = 0;
        idsToBorrow[1] = 1;
        idsToBorrow[2] = 2;
        vm.warp(1000);
        rbf.borrow{value: 3.3 ether}(address(pair721ETH), idsToBorrow, address(0), 0);
        assertEq(test721.ownerOf(0), address(this));
        assertEq(test721.ownerOf(1), address(this));
        assertEq(test721.ownerOf(2), address(this));
    }

    function test_repay() public {

        // Borrow 2 NFTs for 2.2 ETH
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 3));
        uint256[] memory idsToBorrow = new uint256[](2);
        idsToBorrow[0] = 0;
        idsToBorrow[1] = 1;
        vm.warp(1000);
        rbf.borrow{value: 2.2 ether}(address(pair721ETH), idsToBorrow, address(0), 0);

        // Approve sudoshort to spend NFTs
        test721.setApprovalForAll(address(rbf), true);

        // Fails if interest isn't enough
        vm.expectRevert("Too little");
        rbf.repay(idsToBorrow);

        // Fails if not enough NFTs paid pack
        uint256[] memory empty = new uint256[](0);
        vm.expectRevert("Empty");
        rbf.repay{value: 0.01 ether}(empty);

        // Fails if only partially paid back
        uint256[] memory singleId = new uint256[](1);
        singleId[0] = 0;
        vm.expectRevert();
        rbf.repay{value: 0.1 ether}(singleId);

        // Fails if the same ID is used more than once
        idsToBorrow[1] = 0;
        vm.expectRevert();
        rbf.repay{value: 0.01 ether}(idsToBorrow);

        // Repaying works with the right amount of funds and IDs
        // (We pay the minimum 0.01 ETH fee * 2)
        idsToBorrow[1] = 1;
        rbf.repay{value: 0.02 ether}(idsToBorrow);

        // Borrow again
        vm.warp(1100);
        idsToBorrow[0] = 0;
        idsToBorrow[1] = 1;
        rbf.borrow{value: 2.2 ether}(address(pair721ETH), idsToBorrow, address(0), 0);

        // Skip ahead some time, pay no interest
        vm.warp(87500);
        vm.expectRevert("Too little");
        rbf.repay{value: 0.01 ether}(idsToBorrow);

        // Pay the right amount of interest
        rbf.repay{value: 0.0222 ether}(idsToBorrow);
    }

    function test_repayAfterLeaving() public {
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 3));
        uint256[] memory idsToBorrow = new uint256[](2);
        idsToBorrow[0] = 0;
        idsToBorrow[1] = 1;
        vm.warp(1100);
        rbf.borrow{value: 2.2 ether}(address(pair721ETH), idsToBorrow, address(0), 0);
        test721.setApprovalForAll(address(rbf), true);

        // Leave RBF from the pair
        address[] memory pairList = new address[](1);
        pairList[0] = address(pair721ETH);
        rbf.reclaimPairs(pairList);
        assertEq(pair721ETH.owner(), address(this));

        // warp ahead and repay
        // ensure it still succeeds
        vm.warp(87500);
        rbf.repay{value: 0.0222 ether}(idsToBorrow);
    }

    function test_liquidate() public {
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 3));
        uint256[] memory idsToBorrow = new uint256[](2);
        idsToBorrow[0] = 0;
        idsToBorrow[1] = 1;
        vm.warp(1000);
        rbf.borrow{value: 2.2 ether}(address(pair721ETH), idsToBorrow, address(0), 0);
        test721.setApprovalForAll(address(rbf), true);

        vm.deal(address(123), 10 ether);
        vm.prank(address(123));
        vm.expectRevert("Not yet");
        rbf.liquidate(address(this));

        // Skip ahead 7 days plus epsilon
        uint256 newTime = 1000 + 7 days + 1;
        vm.warp(newTime);

        // Attempt to liquidate
        uint256 beforeBalance = address(123).balance;
        uint256 beforePoolBalance = address(pair721ETH).balance;
        vm.prank(address(123));
        rbf.liquidate(address(this));
        uint256 afterBalance = address(123).balance;
        uint256 afterPoolBalance = address(pair721ETH).balance;

        require(afterBalance - beforeBalance >= 0.01 ether); // 1% liquidation bonus goes to caller
        require(afterPoolBalance - beforePoolBalance == 2.178 ether); // 99% of collateral goes to pool
    }

    function test_borrowAndSwap() public {

        // Init RBF
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 1));
        uint256[] memory idsToBorrow = new uint256[](1);
        idsToBorrow[0] = 0;

        // Skip ahead a bit so the first borrow doesn't fail
        vm.warp(1000);

        uint256[] memory empty = new uint256[](0);
        LSSVMPair pairToFill = pairFactory.createPairERC721ETH{value: 0.9 ether}(
            test721, bondingCurve, payable(address(this)), LSSVMPair.PoolType.TRADE, 0, 0, 0.9 ether, address(0), empty
        );

        // Borrow and swap in the same tx
        rbf.borrow{value: 0.2 ether}(address(pair721ETH), idsToBorrow, address(pairToFill), 0.9 ether);
    }

    function test_borrowAndSwapWithFakePool() public {

        // Init RBF
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 1));
        uint256[] memory idsToBorrow = new uint256[](1);
        idsToBorrow[0] = 0;

        // Skip ahead a bit so the first borrow doesn't fail
        vm.warp(1000);

        // Borrow and swap in the same tx for a fake pool
        vm.expectRevert();
        rbf.borrow{value: 0.2 ether}(address(pair721ETH), idsToBorrow, address(this), 0.9 ether);
    }

    function test_borrowAndSwapAndRepay() public {

        // Init RBF
        pair721ETH.transferOwnership(address(rbf), abi.encode(1, 1, 1));
        uint256[] memory idsToBorrow = new uint256[](1);
        idsToBorrow[0] = 0;

        // Skip ahead a bit so the first borrow doesn't fail
        vm.warp(1000);

        uint256[] memory empty = new uint256[](0);
        LSSVMPair pairToFill = pairFactory.createPairERC721ETH{value: 0.9 ether}(
            test721, bondingCurve, payable(address(this)), LSSVMPair.PoolType.TRADE, 0, 0, 0.9 ether, address(0), empty
        );

        // Borrow and swap in the same tx
        rbf.borrow{value: 0.2 ether}(address(pair721ETH), idsToBorrow, address(pairToFill), 0.9 ether);

        // Approve sudoshort to spend NFTs
        test721.setApprovalForAll(address(rbf), true);

        // Repaying works with the right amount of funds and IDs
        // (We pay the minimum 0.01 ETH fee)
        IERC721Mintable(address(test721)).mint(address(this), 4);
        uint256[] memory idsToRepay = new uint256[](1);
        idsToRepay[0] = 4;
        rbf.repay{value: 0.01 ether}(idsToRepay);
    }


    // Mock pair variant call
    function pairVariant() public pure returns (uint256) {
        return 1;
    }

    receive() external payable {}
}
