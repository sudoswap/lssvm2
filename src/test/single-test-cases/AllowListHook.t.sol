// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

import {Test2981} from "../../mocks/Test2981.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {MockCurve} from "../../mocks/MockCurve.sol";
import {Test20} from "../../mocks/Test20.sol";
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
import {LSSVMRouter} from "../../LSSVMRouter.sol";

import {GDACurve} from "../../bonding-curves/GDACurve.sol";
import {LinearCurve} from "../../bonding-curves/LinearCurve.sol";

import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";

import {AllowListHook} from "../../hooks/AllowListHook.sol";

contract AllowListTest is Test, ConfigurableWithRoyalties, UsingLinearCurve, UsingETH, ERC1155Holder, ERC721Holder {
    using SafeTransferLib for address payable;

    ICurve linearCurve;
    ICurve gdaCurve;
    RoyaltyEngine royaltyEngine;
    LSSVMPairFactory pairFactory;
    PropertyCheckerFactory propertyCheckerFactory;
    VeryFastRouter router;
    IERC721 test721;

    AllowListHook hook;

    function setUp() public {
        linearCurve = setupCurve();
        gdaCurve = new GDACurve();

        royaltyEngine = setupRoyaltyEngine();
        ERC2981 royaltyLookup = ERC2981(new Test2981(payable(address(this)), 0));

        test721 = setup721();

        pairFactory = setupFactory(royaltyEngine, payable(address(0)));
        pairFactory.setBondingCurveAllowed(linearCurve, true);
        pairFactory.setBondingCurveAllowed(gdaCurve, true);
        router = new VeryFastRouter(pairFactory);
        pairFactory.setRouterAllowed(LSSVMRouter(payable(address(router))), true);

        // Set up hook
        hook = new AllowListHook();

        // Set up royalties for the test 721
        RoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(
            address(test721), address(royaltyLookup)
        );

        // Mint ID0 #0 to caller
        IERC721Mintable(address(test721)).mint(address(this), 0);

        test721.setApprovalForAll(address(pairFactory), true);
        test721.setApprovalForAll(address(router), true);
    }

    function _setUpPairERC721ForSaleCustom(
        uint128 spotPrice,
        uint128 delta,
        LSSVMPair.PoolType poolType,
        uint256 depositAmount,
        address _propertyChecker,
        uint256[] memory nftIdsToDeposit,
        ICurve specificCurve,
        address specificHook
    ) public returns (LSSVMPair pair) {
        pair = this.setupPairWithPropertyCheckerERC721{value: modifyInputAmount(depositAmount)}(
            PairCreationParamsWithPropertyCheckerERC721({
                factory: pairFactory,
                nft: test721,
                bondingCurve: specificCurve,
                assetRecipient: payable(address(0)),
                poolType: poolType,
                delta: delta,
                fee: 0,
                spotPrice: spotPrice,
                _idList: nftIdsToDeposit,
                initialTokenBalance: depositAmount,
                routerAddress: address(0),
                propertyChecker: _propertyChecker,
                hookAddress: specificHook
            })
        );
    }

    function test_buyFromoolERC721_ETH() public {
        LSSVMPair pair;

        // Create initial pool
        uint256[] memory idToDeposit = new uint256[](1);
        pair = _setUpPairERC721ForSaleCustom(
            1 ether,
            0,
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit,
            linearCurve,
            address(hook)
        );

        // Try to buy it as address(1)
        // Assert that tx fails
        vm.expectRevert();
        vm.deal(address(1), 10 ether);
        vm.startPrank(address(1));
        pair.swapTokenForSpecificNFTs{value: 1 ether}(
            idToDeposit,
            1 ether,
            address(1),
            false,
            address(0)
        );
        vm.stopPrank(); 

        // Set allowlist for address(2)
        address[] memory addressToAllow = new address[](1);
        addressToAllow[0] = address(2);
        hook.modifyAllowList(idToDeposit, addressToAllow);

        // Try to buy as address(2)
        // It shouldn't revert
        vm.deal(address(2), 10 ether);
        vm.startPrank(address(2));
        pair.swapTokenForSpecificNFTs{value: 1 ether}(
            idToDeposit,
            1 ether,
            address(2),
            false,
            address(0)
        );
    }
}
