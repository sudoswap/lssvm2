// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Seaport} from "seaport/Seaport.sol";
import {ConduitController} from "seaport/conduit/ConduitController.sol";
import {ReceivedItem, Schema, SpentItem, AdvancedOrder, OrderParameters, CriteriaResolver, OfferItem, ConsiderationItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ItemType, OrderType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Test721} from "../../mocks/Test721.sol";
import {Test1155} from "../../mocks/Test1155.sol";
import {Test20} from "../../mocks/Test20.sol";
import {Test2981} from "../../mocks/Test2981.sol";

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

import {Sudock} from "../../pkexec/Sudock.sol";

contract Harbor is Test, ERC1155Holder, ERC721Holder {
    Seaport sp;
    ConduitController cc;

    ICurve bondingCurve;
    LSSVMPairFactory pairFactory;
    IERC721 test721;
    IERC1155 test1155;
    ERC20 test20;
    LSSVMPair pair721ERC20;
    LSSVMPair pair1155ERC20;
    LSSVMPair pair721ETH;
    LSSVMPair pair1155ETH;

    Sudock dock;

    function setUp() public {
        cc = new ConduitController();
        sp = new Seaport(address(cc));

        test721 = new Test721();
        test1155 = new Test1155();
        test20 = new Test20();
        Test2981 test2981 = new Test2981(address(1), 500);
        RoyaltyRegistry royaltyRegistry = new RoyaltyRegistry(address(0));
        royaltyRegistry.initialize(address(this));
        royaltyRegistry.setRoyaltyLookupAddress(
            address(test721),
            address(test2981)
        );
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
            5000000000000000,
            address(this)
        );

        // Approve bonding curve
        bondingCurve = new LinearCurve();
        pairFactory.setBondingCurveAllowed(bondingCurve, true);

        // Approve ERC20 and NFTs for factory
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
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 0;
        pair721ETH = pairFactory.createPairERC721ETH(
            test721,
            bondingCurve,
            payable(address(this)),
            LSSVMPair.PoolType.TRADE,
            5 * (10 ** 17), // delta
            10 ** 17, // fee (10%)
            10 ** 18, // spot price
            address(0), // property checker
            ids
        );

        dock = new Sudock((pairFactory), address(sp));

        // Dock the pool
        pair721ETH.transferOwnership(address(dock), "");
    }

    function spentItemsToOfferItems(
        SpentItem[] memory items
    ) private returns (OfferItem[] memory) {
        OfferItem[] memory offers = new OfferItem[](items.length);
        for (uint i; i < items.length; ++i) {
            SpentItem memory item = items[i];
            offers[i] = OfferItem({
                itemType: item.itemType,
                token: item.token,
                identifierOrCriteria: item.identifier,
                startAmount: item.amount,
                endAmount: item.amount
            });
        }
        return offers;
    }

    function receivedItemsToConsiderationItems(
        ReceivedItem[] memory items
    ) private returns (ConsiderationItem[] memory) {
        ConsiderationItem[] memory offers = new ConsiderationItem[](
            items.length
        );
        for (uint i; i < items.length; ++i) {
            ReceivedItem memory item = items[i];
            offers[i] = ConsiderationItem({
                itemType: item.itemType,
                token: item.token,
                identifierOrCriteria: item.identifier,
                startAmount: item.amount,
                endAmount: item.amount,
                recipient: item.recipient
            });
        }
        return offers;
    }

    function testSudockBuys721ForETH() public {
        // Buy ID 1
        SpentItem[] memory minimumReceived = new SpentItem[](1);
        minimumReceived[0] = SpentItem({
            itemType: ItemType.ERC721,
            token: address(test721),
            identifier: 1,
            amount: 1
        });

        SpentItem[] memory empty = new SpentItem[](0);

        (
            SpentItem[] memory spentItems,
            ReceivedItem[] memory considerationItems
        ) = dock.previewOrder(
                address(sp),
                address(sp),
                minimumReceived,
                empty,
                abi.encode(address(pair721ETH))
            );

        // Construct Seaport args
        OrderParameters memory orderParameters = OrderParameters(
            address(dock),
            address(0),
            spentItemsToOfferItems(spentItems),
            receivedItemsToConsiderationItems(considerationItems),
            OrderType.CONTRACT,
            block.timestamp,
            block.timestamp + 1000,
            bytes32(0),
            0,
            bytes32(0),
            considerationItems.length
        );
        AdvancedOrder memory advancedOrder = AdvancedOrder(
            orderParameters,
            1,
            1,
            "",
            abi.encode(address(pair721ETH))
        );

        uint256 totalETHNeeded = 0;
        for (uint i; i < considerationItems.length; ++i) {
          totalETHNeeded += considerationItems[i].amount;
        }

        sp.fulfillAdvancedOrder{value: totalETHNeeded}(
            advancedOrder,
            new CriteriaResolver[](0),
            bytes32(0),
            address(0)
        );
    }

    receive() external payable {

    }
}
