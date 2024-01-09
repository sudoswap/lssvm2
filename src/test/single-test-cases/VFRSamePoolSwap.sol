// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

import {Test2981} from "../../mocks/Test2981.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {MockCurve} from "../../mocks/MockCurve.sol";
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
import {UsingExponentialCurve} from "../../test/mixins/UsingExponentialCurve.sol";
import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {ILSSVMPair} from "../../ILSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {VeryFastRouter} from "../../VeryFastRouter.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";

import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";

contract VFRSamePoolSwap is Test, ConfigurableWithRoyalties, UsingExponentialCurve, UsingETH {
    ICurve bondingCurve;
    RoyaltyEngine royaltyEngine;
    LSSVMPairFactory pairFactory;
    PropertyCheckerFactory propertyCheckerFactory;
    VeryFastRouter router;
    IERC721 test721;

    function setUp() public {
        bondingCurve = setupCurve();

        royaltyEngine = setupRoyaltyEngine();
        ERC2981 royaltyLookup = ERC2981(new Test2981(payable(address(this)), 500));

        test721 = setup721();

        pairFactory = setupFactory(royaltyEngine, payable(address(0)));
        pairFactory.setBondingCurveAllowed(bondingCurve, true);
        pairFactory.changeProtocolFeeMultiplier(5000000000000000);
        router = new VeryFastRouter(pairFactory);
        pairFactory.setRouterAllowed(LSSVMRouter(payable(address(router))), true);

        // Set up royalties for the test 721
        RoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(
            address(test721), address(royaltyLookup)
        );

        // Mint ids to caller
        IERC721Mintable(address(test721)).mint(address(this), 0);
        IERC721Mintable(address(test721)).mint(address(this), 1);

        test721.setApprovalForAll(address(pairFactory), true);
        test721.setApprovalForAll(address(router), true);
    }

    function test_foo() public {
        uint256[] memory idsInPair = new uint256[](1);
        idsInPair[0] = 0;

        uint256[] memory ownedIds = new uint256[](1);
        ownedIds[0] = 1;

        // Create pair
        LSSVMPair pair = pairFactory.createPairERC721ETH{value: 0.3 ether}(
            test721,
            bondingCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            1500000000000000000,
            10000000000000000,
            157977883096366509,
            0x0000000000000000000000000000000000000000,
            idsInPair,
            address(0),
            address(0)
        );

        // Swap both for the ID 0 and sell the ID 1
        (,,, uint256 sellQuote,,) = pair.getSellNFTQuote(1, 1);
        (,,, uint256 buyQuote,,) = pair.getBuyNFTQuote(1, 1);

        VeryFastRouter.BuyOrderWithPartialFill[] memory buys = new VeryFastRouter.BuyOrderWithPartialFill[](1);
        uint256[] memory maxCost = new uint256[](1);
        maxCost[0] = buyQuote;
        buys[0] = VeryFastRouter.BuyOrderWithPartialFill({
            pair: pair,
            isERC721: true,
            nftIds: idsInPair,
            maxInputAmount: buyQuote,
            ethAmount: buyQuote,
            expectedSpotPrice: pair.spotPrice(),
            maxCostPerNumNFTs: maxCost
        });

        uint256[] memory minOutput = new uint256[](1);
        minOutput[0] = sellQuote;
        VeryFastRouter.SellOrderWithPartialFill[] memory sells = new VeryFastRouter.SellOrderWithPartialFill[](1);

        sells[0] = VeryFastRouter.SellOrderWithPartialFill({
            pair: pair,
            isETHSell: true,
            isERC721: true,
            nftIds: ownedIds,
            doPropertyCheck: false,
            propertyCheckParams: "",
            expectedSpotPrice: pair.spotPrice(),
            minExpectedOutput: sellQuote,
            minExpectedOutputPerNumNFTs: minOutput
        });

        // Create swap order with the values and attempt to fill
        VeryFastRouter.Order memory order = VeryFastRouter.Order({
            buyOrders: buys,
            sellOrders: sells,
            tokenRecipient: payable(address(this)),
            nftRecipient: payable(address(this)),
            recycleETH: true
        });
        router.swap{value: buyQuote}(order);
    }
}
