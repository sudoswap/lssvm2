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

contract ZeroExRouterTest is Test, ERC1155Holder {
    ICurve bondingCurve;
    LSSVMPairFactory pairFactory;
    IERC721 test721;
    IERC1155 test1155;
    ERC20 test20;
    MockDex dex;
    ZeroExRouter router;

    LSSVMPair pair721;
    LSSVMPair pair1155;

    function setUp() public {
        test721 = new Test721();
        test1155 = new Test1155();
        test20 = new Test20();
        dex = new MockDex(address(test20));
        router = new ZeroExRouter();

        RoyaltyRegistry royaltyRegistry = new RoyaltyRegistry(address(0));
        royaltyRegistry.initialize(address(this));
        RoyaltyEngine royaltyEngine = new RoyaltyEngine(address(royaltyRegistry));

        LSSVMPairERC721ETH erc721ETHTemplate = new LSSVMPairERC721ETH(royaltyEngine);
        LSSVMPairERC721ERC20 erc721ERC20Template = new LSSVMPairERC721ERC20(royaltyEngine);
        LSSVMPairERC1155ETH erc1155ETHTemplate = new LSSVMPairERC1155ETH(royaltyEngine);
        LSSVMPairERC1155ERC20 erc1155ERC20Template = new LSSVMPairERC1155ERC20(royaltyEngine);
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
        ICurve curve = new LinearCurve();
        pairFactory.setBondingCurveAllowed(curve, true);

        // Approve ERC20 and NFTs for factory
        test721.setApprovalForAll(address(pairFactory), true);
        test1155.setApprovalForAll(address(pairFactory), true);
        test20.approve(address(pairFactory), 100 ether);

        // Initialize mint of tokens
        IMintable(address(test20)).mint(address(this), 100 ether);
        IERC721Mintable(address(test721)).mint(address(this), 0);
        IERC721Mintable(address(test721)).mint(address(this), 1);
        IERC1155Mintable(address(test1155)).mint(address(this), 0, 10);

        // Give the mock dex enough tokens
        vm.deal(address(dex), 100 ether);
        IMintable(address(test20)).mint(address(dex), 100 ether);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        // Create ERC721 ERC20 trade pool
        pair721 = pairFactory.createPairERC721ERC20(
            LSSVMPairFactory.CreateERC721ERC20PairParams({
                token: test20,
                nft: test721,
                bondingCurve: curve,
                assetRecipient: payable(address(this)),
                poolType: LSSVMPair.PoolType.TRADE,
                delta: 0,
                fee: 0,
                spotPrice: 1 ether,
                propertyChecker: address(0),
                initialNFTIDs: ids,
                initialTokenBalance: 10 ether
            })
        );

        // Create ERC1155 ERC20 trade pool
        pair1155 = pairFactory.createPairERC1155ERC20(
            LSSVMPairFactory.CreateERC1155ERC20PairParams({
                token: test20,
                nft: test1155,
                bondingCurve: curve,
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
    }

    function test_ethToERC20ToERC1155() public {
        uint256[] memory swapInfo = new uint256[](1);
        swapInfo[0] = 5;

        // Encode swap to mock dex from ETH to ERC20
        // Then swap ERC20 for ID #0
        router.swapETHForTokensThenTokensForNFT{value: 5 ether}(
            address(test20),
            payable(address(dex)),
            abi.encodeCall(dex.swapETHtoERC20, (0)),
            address(pair1155),
            swapInfo,
            0,
            5
        );
        assertEq(IERC1155(address(test1155)).balanceOf(address(this), 0), 10);
    }

    function test_ethToERC20ToERC721() public {
        uint256[] memory idsToSwap = new uint256[](1);
        idsToSwap[0] = 0;

        // Encode swap to mock dex from ETH to ERC20
        // Then swap ERC20 for ID #0
        router.swapETHForTokensThenTokensForNFT{value: 1 ether}(
            address(test20),
            payable(address(dex)),
            abi.encodeCall(dex.swapETHtoERC20, (0)),
            address(pair721),
            idsToSwap,
            0,
            1
        );
        assertEq(IERC721(address(test721)).ownerOf(0), address(this));
    }

    function test_erc721ToERC20ToETH() public {
        IERC721(test721).safeTransferFrom(
            address(this),
            address(router),
            1,
            abi.encode(
                address(pair721),
                1 ether,
                address(test20),
                address(dex),
                1 ether,
                abi.encodeCall(MockDex.swapERC20ToETH, (1 ether))
            )
        );
        assertEq(IERC721(address(test721)).ownerOf(1), address(pair721));
    }

    function test_erc1155ToERC20ToETH() public {
        IERC1155(test1155).safeTransferFrom(
            address(this),
            address(router),
            0,
            5,
            abi.encode(
                address(pair1155),
                5 ether,
                address(test20),
                address(dex),
                5 ether,
                abi.encodeCall(MockDex.swapERC20ToETH, (5 ether))
            )
        );
        assertEq(IERC1155(test1155).balanceOf(address(this), 0), 0);
    }

    receive() external payable {}
}
