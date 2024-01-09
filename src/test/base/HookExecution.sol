// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";
import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Test721} from "../../mocks/Test721.sol";

import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {GDACurve} from "../../bonding-curves/GDACurve.sol";
import {LinearCurve} from "../../bonding-curves/LinearCurve.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {IERC1155Mintable} from "../interfaces/IERC1155Mintable.sol";
import {IPropertyChecker} from "../../property-checking/IPropertyChecker.sol";
import {RangePropertyChecker} from "../../property-checking/RangePropertyChecker.sol";
import {MerklePropertyChecker} from "../../property-checking/MerklePropertyChecker.sol";
import {PropertyCheckerFactory} from "../../property-checking/PropertyCheckerFactory.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {ILSSVMPair} from "../../ILSSVMPair.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {RoyaltyEngine} from "../../RoyaltyEngine.sol";
import {LSSVMPairERC20} from "../../LSSVMPairERC20.sol";
import {VeryFastRouter} from "../../VeryFastRouter.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";

import {DummyHooks} from "../../hooks/DummyHooks.sol";
import {OrderBhook} from "../../hooks/OrderBhook.sol";
import {Test20} from "../../mocks/Test20.sol";

// Future TODO:
// - depositing NFTs triggers for ERC1155 pools
// - depositing other NFTs does not trigger ERC1155 pools
// - withdrawing NFTs triggers for ERC1155 pools
// - depositing NFTs triggers for ERC1155 pools

abstract contract HookExecution is Test, ERC721Holder, ERC1155Holder, ConfigurableWithRoyalties {
    using SafeTransferLib for address payable;

    ICurve bondingCurve;

    ICurve gdaCurve;
    ICurve linearCurve;

    RoyaltyEngine royaltyEngine;
    LSSVMPairFactory pairFactory;
    PropertyCheckerFactory propertyCheckerFactory;
    ERC2981 test2981;
    IERC721Mintable nft;

    uint128 delta;
    uint128 spotPrice;
    address hookAddress;
    address bhookAddress;

    address constant ROUTER_CALLER = address(1);
    address constant TOKEN_RECIPIENT = address(420);
    address constant NFT_RECIPIENT = address(0x69);
    address constant PAIR_RECIPIENT = address(1111111111);
    uint256 constant START_INDEX = 0;
    uint256 constant END_INDEX = 10;

    // Events to check from DummyHooks
    event e_afterNewPair();
    event e_afterSwapNFTInPair(
        uint256 _tokensOut, uint256 _tokensOutProtocolFee, uint256 _tokensOutRoyalty, uint256[] _nftsIn
    );
    event e_afterSwapNFTOutPair(
        uint256 _tokensIn, uint256 _tokensInProtocolFee, uint256 _tokensInRoyalty, uint256[] _nftsOut
    );
    event e_afterDeltaUpdate(uint128 _oldDelta, uint128 _newDelta);
    event e_afterSpotPriceUpdate(uint128 _oldSpotPrice, uint128 _newSpotPrice);
    event e_afterFeeUpdate(uint96 _oldFee, uint96 _newFee);
    event e_afterNFTWithdrawal(uint256[] _nftsOut);
    event e_afterTokenWithdrawal(uint256 _tokensOut);

    // Still need tests
    event e_syncForPair(address pairAddress, uint256 _tokensIn, uint256[] _nftsIn);

    function setUp() public {
        bondingCurve = setupCurve();
        gdaCurve = new GDACurve();
        linearCurve = new LinearCurve();
        royaltyEngine = setupRoyaltyEngine();
        pairFactory = setupFactory(royaltyEngine, payable(address(0)));
        pairFactory.setBondingCurveAllowed(bondingCurve, true);
        pairFactory.setBondingCurveAllowed(linearCurve, true);
        pairFactory.setBondingCurveAllowed(gdaCurve, true);
        test2981 = setup2981();

        MerklePropertyChecker checker1 = new MerklePropertyChecker();
        RangePropertyChecker checker2 = new RangePropertyChecker();
        propertyCheckerFactory = new PropertyCheckerFactory(checker1, checker2);

        (delta, spotPrice) = getReasonableDeltaAndSpotPrice();

        // Give the router caller a large amount of ETH
        vm.deal(ROUTER_CALLER, 1e18 ether);

        hookAddress = address(new DummyHooks());
        bhookAddress = address(new OrderBhook(pairFactory, address(this)));
        OrderBhook(bhookAddress).addCurve(address(linearCurve));
        nft = _setUpERC721(address(this), address(this));
    }

    function _setUpERC721(address nftRecipient, address factoryCaller) internal returns (IERC721Mintable _nft) {
        _nft = IERC721Mintable(address(new Test721()));
        IRoyaltyRegistry(royaltyEngine.ROYALTY_REGISTRY()).setRoyaltyLookupAddress(address(_nft), address(test2981));

        for (uint256 i = START_INDEX; i <= END_INDEX; i++) {
            _nft.mint(nftRecipient, i);
        }
        vm.prank(factoryCaller);
        _nft.setApprovalForAll(address(pairFactory), true);
    }

    function _setUpPairERC721ForSale(
        LSSVMPair.PoolType poolType,
        uint256 depositAmount,
        address _propertyChecker,
        uint256[] memory nftIdsToDeposit
    ) public returns (LSSVMPair pair) {
        pair = this.setupPairWithPropertyCheckerERC721{value: modifyInputAmount(depositAmount)}(
            PairCreationParamsWithPropertyCheckerERC721({
                factory: pairFactory,
                nft: nft,
                bondingCurve: bondingCurve,
                assetRecipient: payable(address(0)),
                poolType: poolType,
                delta: delta,
                fee: 1, // set a non-zero fee
                spotPrice: spotPrice,
                _idList: nftIdsToDeposit,
                initialTokenBalance: depositAmount,
                routerAddress: address(0),
                propertyChecker: _propertyChecker,
                hookAddress: hookAddress
            })
        );
    }

    function _setUpPairERC721ForSaleCustom(
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
                nft: nft,
                bondingCurve: specificCurve,
                assetRecipient: payable(address(0)),
                poolType: poolType,
                delta: delta,
                fee: 1,
                spotPrice: spotPrice,
                _idList: nftIdsToDeposit,
                initialTokenBalance: depositAmount,
                routerAddress: address(0),
                propertyChecker: _propertyChecker,
                hookAddress: specificHook
            })
        );
    }

    function test_afterNewPair() public {
        uint256[] memory empty = new uint256[](0);
        vm.expectEmit(false, false, false, true);
        emit e_afterNewPair();
        _setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, 0, address(0), empty);
    }

    function test_afterSwapNFTInPair() public {
        uint256[] memory empty = new uint256[](0);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            empty
        );
        (,,, uint256 outputAmount, uint256 protocolFee, uint256 royaltyAmount) = pair.getSellNFTQuote(0, 1);
        nft.setApprovalForAll(address(pair), true);
        uint256[] memory idToSell = new uint256[](1);
        vm.expectEmit(false, false, false, true);
        emit e_afterSwapNFTInPair(outputAmount, protocolFee, royaltyAmount, idToSell);
        pair.swapNFTsForToken(idToSell, outputAmount, payable(address(this)), false, address(0));
    }

    function test_afterSwapNFTOutPair() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );
        (,,, uint256 inputAmount, uint256 protocolFee, uint256 royaltyAmount) = pair.getBuyNFTQuote(0, 1);
        vm.expectEmit(false, false, false, true);
        emit e_afterSwapNFTOutPair(inputAmount, protocolFee, royaltyAmount, idToDeposit);
        pair.swapTokenForSpecificNFTs{value: modifyInputAmount(inputAmount)}(
            idToDeposit, inputAmount, payable(address(this)), false, address(0)
        );
    }

    function test_afterDeltaUpdate() public {
        uint256[] memory empty = new uint256[](0);
        LSSVMPair pair = _setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, 0, address(0), empty);
        uint128 oldDelta = pair.delta();
        vm.expectEmit(false, false, false, true);
        emit e_afterDeltaUpdate(oldDelta, oldDelta * 2);
        pair.changeDelta(oldDelta * 2);
    }

    function test_afterSpotPriceUpdate() public {
        uint256[] memory empty = new uint256[](0);
        LSSVMPair pair = _setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, 0, address(0), empty);
        uint128 oldSpotPrice = pair.spotPrice();
        vm.expectEmit(false, false, false, true);
        emit e_afterSpotPriceUpdate(oldSpotPrice, oldSpotPrice * 2);
        pair.changeSpotPrice(oldSpotPrice * 2);
    }

    function test_afterFeeUpdate() public {
        uint256[] memory empty = new uint256[](0);
        LSSVMPair pair = _setUpPairERC721ForSale(LSSVMPair.PoolType.TRADE, 0, address(0), empty);
        uint96 oldFee = pair.fee();
        vm.expectEmit(false, false, false, true);
        emit e_afterFeeUpdate(oldFee, oldFee * 2);
        pair.changeFee(oldFee * 2);
    }

    function test_afterNFTWithdrawal() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );
        // Expect to get the withdraw event
        vm.expectEmit(false, false, false, true);
        emit e_afterNFTWithdrawal(idToDeposit);
        pair.withdrawERC721(IERC721(address(nft)), idToDeposit);
    }

    function testFail_afterNFTWithdrawal() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );

        // Expect to *not* get the withdraw event if creating a new NFT
        IERC721Mintable otherNFT = IERC721Mintable(address(new Test721()));
        otherNFT.mint(address(this), 0);
        otherNFT.transferFrom(address(this), address(pair), 0);
        vm.expectEmit(false, false, false, true);
        emit e_afterNFTWithdrawal(idToDeposit);
        pair.withdrawERC721(IERC721(address(otherNFT)), idToDeposit);
    }

    function test_afterTokenWithdrawal() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );
        vm.expectEmit(false, false, false, true);
        emit e_afterTokenWithdrawal(10 ether);
        withdrawTokens(pair);
    }

    function testFail_afterTokenWithdrawalETH() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );
        Test20 newToken = new Test20();
        newToken.mint(address(pair), 1);
        vm.expectEmit(false, false, false, true);

        // If ETH pair and withdrawing ERC20 tokens, cannot trigger callback
        if (getTokenAddress() == address(0)) {
            emit e_afterTokenWithdrawal(10 ether);
            pair.withdrawERC20(ERC20(address(newToken)), 1);
        } else {
            require(1 == 0, "Always revert");
        }
    }

    function test_syncForPairETHOnDepositETH() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );
        // Deposit ETH into the pair
        if (getTokenAddress() == address(0)) {
            vm.deal(address(this), 1 ether);
            uint256[] memory empty = new uint256[](0);

            vm.expectEmit(false, false, false, true);
            emit e_syncForPair(address(pair), 0.1 ether, empty);
            payable(address(pair)).safeTransferETH(0.1 ether);
        }
    }

    function testFail_syncForPairERC20OnDepositETH() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );
        // Deposit ETH into the pair
        if (getTokenAddress() != address(0)) {
            vm.deal(address(this), 1 ether);
            uint256[] memory empty = new uint256[](0);

            vm.expectEmit(false, false, false, true);
            emit e_syncForPair(address(pair), 0.1 ether, empty);
            payable(address(pair)).safeTransferETH(0.1 ether);
        } else {
            require(1 == 0, "Always revert");
        }
    }

    function test_syncForPairERC20OnDepositERC20() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );
        // Deposit ERC20 into the pair if it's an ERC20 pair
        if (getTokenAddress() != address(0)) {
            uint256[] memory empty = new uint256[](0);
            vm.expectEmit(false, false, false, true);
            emit e_syncForPair(address(pair), 0.1 ether, empty);
            pairFactory.depositERC20(ERC20(getTokenAddress()), address(pair), 0.1 ether);
        }
    }

    function testFail_syncForPairETHOnDepositERC20() public {
        uint256[] memory idToDeposit = new uint256[](1);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            idToDeposit
        );
        // Deposit ERC20 into the pair if it's an ERC20 pair
        if (getTokenAddress() == address(0)) {
            Test20 token = new Test20();
            token.mint(address(this), 0.1 ether);
            ERC20(address(token)).approve(address(pairFactory), 0.1 ether);
            uint256[] memory empty = new uint256[](0);
            vm.expectEmit(false, false, false, true);
            emit e_syncForPair(address(pair), 0.1 ether, empty);
            pairFactory.depositERC20(ERC20(address(token)), address(pair), 0.1 ether);
        } else {
            require(1 == 0, "Always revert");
        }
    }

    function test_syncForPairERC721OnDepositERC721() public {
        uint256[] memory empty = new uint256[](0);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            empty
        );
        uint256[] memory id0 = new uint256[](1);
        vm.expectEmit(false, false, false, true);
        emit e_syncForPair(address(pair), 0, id0);
        pairFactory.depositNFTs(IERC721(address(nft)), id0, address(pair));
    }

    function testFail_syncForPairERC721OnDepositERC721() public {
        uint256[] memory empty = new uint256[](0);
        LSSVMPair pair = _setUpPairERC721ForSale(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            empty
        );
        IERC721Mintable newNFT = _setUpERC721(address(this), address(this));
        uint256[] memory id0 = new uint256[](1);
        vm.expectEmit(false, false, false, true);
        emit e_syncForPair(address(pair), 0, id0);
        pairFactory.depositNFTs(IERC721(address(newNFT)), id0, address(pair));
    }

    // Test inclusion
    // Creating a linear pool will show it as valid
    // Creating a gda pool will not register it (expect fail)
    function test_registersPoolCreation() public {
        uint256[] memory empty = new uint256[](0);
        LSSVMPair pair;

        pair = _setUpPairERC721ForSaleCustom(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            empty,
            linearCurve,
            bhookAddress
        );

        // Cannot manually call afterNewPair on a pair if the hook is set to address(0)
        vm.expectRevert();
        OrderBhook(bhookAddress).afterNewPair();

        // Cannot manually call syncForPair on a pair if the hook is set to address(0)
        LSSVMPair noHookPair = _setUpPairERC721ForSaleCustom(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            empty,
            linearCurve,
            address(0)
        );
        vm.expectRevert(OrderBhook.OrderBhook__IncorrectHookAddress.selector);
        OrderBhook(bhookAddress).syncForPair(address(noHookPair), 0, empty);

        // Cannot add GDA pool
        vm.expectRevert(OrderBhook.OrderBhook__BondingCurveNotAllowed.selector);
        delta = uint128(1e9 + 1) << 88;
        spotPrice = 1e18;
        _setUpPairERC721ForSaleCustom(
            LSSVMPair.PoolType.TRADE,
            10 ether, // nonzero deposit amount
            address(0),
            empty,
            gdaCurve,
            bhookAddress
        );
    }
}
