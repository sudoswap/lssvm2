// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

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
import {UsingMockCurve} from "../../test/mixins/UsingMockCurve.sol";
import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {ILSSVMPair} from "../../ILSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {VeryFastRouter} from "../../VeryFastRouter.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";

contract VeryFastRouterWithMockCurve is Test, ConfigurableWithRoyalties, UsingMockCurve, UsingETH {
    ICurve bondingCurve;
    MockCurve mockCurve;
    RoyaltyEngine royaltyEngine;
    LSSVMPairFactory pairFactory;
    PropertyCheckerFactory propertyCheckerFactory;
    VeryFastRouter router;
    IERC721 test721;

    function setUp() public {
        bondingCurve = setupCurve();
        mockCurve = MockCurve(address(bondingCurve));

        royaltyEngine = setupRoyaltyEngine();
        pairFactory = setupFactory(royaltyEngine, payable(address(0)));
        pairFactory.setBondingCurveAllowed(bondingCurve, true);

        router = new VeryFastRouter(pairFactory);
        test721 = setup721();
    }

    function test_clientSideQuoteRevert() public {
        LSSVMPair pair721 = this.setupPairERC721(
            pairFactory,
            test721,
            bondingCurve,
            payable(address(0)), // asset recipient
            LSSVMPair.PoolType.TRADE,
            0,
            0, // 0% for trade fee
            0,
            new uint256[](0),
            0,
            address(0)
        );

        // Ensure it reverts on buy quote
        mockCurve.setBuyError(1);
        vm.expectRevert("Bonding curve quote error");
        router.getNFTQuoteForBuyOrderWithPartialFill(pair721, 1, 0);

        // Ensure it reverts on sell quote
        mockCurve.setSellError(1);
        vm.expectRevert("Bonding curve quote error");
        router.getNFTQuoteForSellOrderWithPartialFill(pair721, 1, 0, 0);
    }
}
