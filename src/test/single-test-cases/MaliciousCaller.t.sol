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
import {UsingLinearCurve} from "../../test/mixins/UsingLinearCurve.sol";
import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {LSSVMPairETH} from "../../LSSVMPairETH.sol";
import {ILSSVMPair} from "../../ILSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {VeryFastRouter} from "../../VeryFastRouter.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";

contract MaliciousCaller is Test, ConfigurableWithRoyalties, UsingLinearCurve, UsingETH {
    ICurve bondingCurve;
    RoyaltyEngine royaltyEngine;
    LSSVMPairFactory pairFactory;
    IERC721 test721;

    address payable ASSET_RECIPIENT = payable(address(69));

    function setUp() public {
        bondingCurve = setupCurve();
        royaltyEngine = setupRoyaltyEngine();
        pairFactory = setupFactory(royaltyEngine, payable(address(0)));
        pairFactory.setBondingCurveAllowed(bondingCurve, true);
        test721 = setup721();
        pairFactory.changeProtocolFeeMultiplier(0.01 ether);
    }

    function test_callETHPoolSwapTokensWithNoETH() public {
        Test721(address(test721)).mint(address(this), 1);
        test721.setApprovalForAll(address(pairFactory), true);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        LSSVMPair pair721 = this.setupPairERC721{value: 10 ether}(
            pairFactory,
            test721,
            bondingCurve,
            ASSET_RECIPIENT,
            LSSVMPair.PoolType.TRADE,
            0.1 ether, // delta
            0.1 ether, // 10% for trade fee
            1 ether, // spot price
            ids,
            10 ether,
            address(0)
        );
        vm.expectRevert(LSSVMPairETH.LSSVMPairETH__InsufficientInput.selector);
        pair721.swapTokenForSpecificNFTs(ids, 10 ether, address(this), false, address(0));
    }
}
