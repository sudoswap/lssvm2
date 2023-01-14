// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

import {ConfigurableWithRoyalties} from "../mixins/ConfigurableWithRoyalties.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {LSSVMPairETH} from "../../LSSVMPairETH.sol";
import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {IOwnable} from "../interfaces/IOwnable.sol";
import {LSSVMPairERC20} from "../../LSSVMPairERC20.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {ILSSVMPairFactoryLike} from "../../ILSSVMPairFactoryLike.sol";

import {StandardAgreement} from "../../agreements/StandardAgreement.sol";
import {StandardAgreementFactory} from "../../agreements/StandardAgreementFactory.sol";
import {Splitter} from "../../agreements/Splitter.sol";

import {Test20} from "../../mocks/Test20.sol";
import {Test721} from "../../mocks/Test721.sol";
import {Test1155} from "../../mocks/Test1155.sol";
import {MockPair} from "../../mocks/MockPair.sol";

abstract contract AgreementE2E is
    Test,
    ERC721Holder,
    ConfigurableWithRoyalties
{
    uint128 delta = 1.1 ether;
    uint128 spotPrice = 20 ether;
    uint256 tokenAmount = 100 ether;
    uint256 numItems = 3;
    uint256[] idList;
    ERC2981 test2981;
    IERC721 test721;
    IERC721 test721Other;
    ERC20 testERC20;
    ICurve bondingCurve;
    LSSVMPairFactory factory;
    address payable constant feeRecipient = payable(address(69));
    LSSVMPair pair;
    MockPair mockPair;
    RoyaltyRegistry royaltyRegistry;
    StandardAgreementFactory agreementFactory;

    function setUp() public {
        bondingCurve = setupCurve();
        test721 = setup721();
        test2981 = setup2981();
        test721Other = new Test721();
        royaltyRegistry = setupRoyaltyRegistry();

        // Set a royalty override
        royaltyRegistry.setRoyaltyLookupAddress(
            address(test721),
            address(test2981)
        );

        // Set up the pair templates and pair factory
        LSSVMPairETH ethTemplate = new LSSVMPairETH(royaltyRegistry);
        LSSVMPairERC20 erc20Template = new LSSVMPairERC20(royaltyRegistry);
        factory = new LSSVMPairFactory(
            ethTemplate,
            erc20Template,
            feeRecipient,
            0, // Zero protocol fee to make calculations easier
            address(this)
        );
        factory.setBondingCurveAllowed(bondingCurve, true);
        test721.setApprovalForAll(address(factory), true);
        // Mint IDs from 1 to numItems to the caller, to deposit into the pair
        for (uint256 i = 1; i <= numItems; i++) {
            IERC721Mintable(address(test721)).mint(address(this), i);
            idList.push(i);
        }
        pair = this.setupPair{value: modifyInputAmount(tokenAmount)}(
            factory,
            test721,
            bondingCurve,
            payable(address(0)), // asset recipient
            LSSVMPair.PoolType.TRADE,
            delta,
            0, // 0% for trade fee
            spotPrice,
            idList,
            tokenAmount,
            address(0)
        );
        testERC20 = ERC20(address(new Test20()));
        IMintable(address(testERC20)).mint(address(pair), 1 ether);
        test721.setApprovalForAll(address(pair), true);
        testERC20.approve(address(pair), 10000 ether);

        // Agreement setup
        Splitter splitterImplementation = new Splitter();
        StandardAgreement agreementImplementation = new StandardAgreement(
            splitterImplementation,
            factory
        );
        agreementFactory = new StandardAgreementFactory(
            agreementImplementation
        );
        mockPair = new MockPair();
    }

    // Pair Factory permissions with adding/removing Agreements and toggling override royalty bps for pools

    // An authorized caller can correctly add/remove an Agreement on the factory
    function test_addAgreementAsAuth() public {
        address agreementAddress = address(69420);
        factory.toggleAgreementForCollection(
            agreementAddress,
            address(test721),
            true
        );
        assertEq(
            factory.authorizedAgreement(agreementAddress),
            address(test721)
        );
        factory.toggleAgreementForCollection(
            agreementAddress,
            address(test721),
            false
        );
        assertEq(factory.authorizedAgreement(agreementAddress), address(0));
    }

    // An unauthorized caller cannot add/remove an Agreement on the factory
    function testFail_addAgreementAsNotAuth() public {
        IOwnable(address(test721)).transferOwnership(address(12345));
        factory.toggleAgreementForCollection(
            address(1),
            address(test721),
            true
        );
    }

    function testFail_removeAgreementAsNotAuth() public {
        IOwnable(address(test721)).transferOwnership(address(12345));
        factory.toggleAgreementForCollection(
            address(1),
            address(test721),
            false
        );
    }

    // An authorized Agreement can set/remove a pair specific royalty bps to be applied
    function test_setPairSpecificRoyaltyBps() public {
        factory.toggleAgreementForCollection(
            address(this),
            address(test721),
            true
        );
        uint96 newBps = 12345;
        factory.toggleBpsForPairInAgreement(address(pair), newBps, true);
        (bool isInAgreement, uint96 royaltyBps) = factory.agreementForPair(
            address(pair)
        );
        assertEq(isInAgreement, true);
        assertEq(royaltyBps, newBps);
        factory.toggleBpsForPairInAgreement(address(pair), newBps, false);
        (isInAgreement, royaltyBps) = factory.agreementForPair(address(pair));
        assertEq(isInAgreement, false);
    }

    // An Agreement cannot toggle royalty bps for a pair if the underlying nft collection is different than what
    // the Agreement is authorized for
    function testFail_setPairSpecificRoyaltyBpsForDiffNFTPair() public {
        factory.toggleAgreementForCollection(
            address(this),
            address(test721Other),
            true
        );
        uint96 newBps = 12345;
        factory.toggleBpsForPairInAgreement(address(pair), newBps, true);
    }

    // An Agreement cannot set pair specific royalty bps for a non-pair address
    function testFail_setPairSpecificRoyaltyBpsForNonPool() public {
        factory.toggleAgreementForCollection(
            address(this),
            address(test721),
            true
        );
        uint96 newBps = 12345;
        factory.toggleBpsForPairInAgreement(address(this), newBps, true);
    }

    // A non-Agreement caller cannot set the pair-specific royalty bps
    function testFail_setPairSpecificRoyaltyBpsNotAuth() public {
        uint96 newBps = 12345;
        factory.toggleBpsForPairInAgreement(address(pair), newBps, true);
    }

    // A non-Agreement caller cannot set the pair-specific royalty bps even if it was previously authorized
    function testFail_setPairSpecificRoyaltyBpsNotAuthEvenAfterPrevAuth()
        public
    {
        factory.toggleAgreementForCollection(
            address(this),
            address(test721),
            true
        );
        factory.toggleAgreementForCollection(
            address(this),
            address(test721),
            false
        );
        uint96 newBps = 12345;
        factory.toggleBpsForPairInAgreement(address(pair), newBps, true);
    }

    // Standard Agreement + Agreement Factory tests

    // Creating a Standard Agreement works as expected, values are as expected
    function test_createAgreementFromFactory() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 royaltyBps = 3;
        StandardAgreement newAgreement = agreementFactory.createAgreement(
            agreementFeeRecipient,
            ethCost,
            secDuration,
            feeSplitBps,
            royaltyBps
        );
        assertEq(newAgreement.agreementFeeRecipient(), agreementFeeRecipient);
        assertEq(newAgreement.getAgreementCost(), ethCost);
        assertEq(newAgreement.getLockDuration(), secDuration);
        assertEq(newAgreement.getFeeSplitBps(), feeSplitBps);
        assertEq(newAgreement.getAgreementRoyaltyBps(), royaltyBps);
        assertEq(IOwnable(address(newAgreement)).owner(), address(this));
        newAgreement.setAgreementFeeRecipient(payable(address(this)));
        assertEq(newAgreement.agreementFeeRecipient(), address(this));
    }

    // A pair can enter a Standard Agreement if authorized
    function test_enterAgreementForPool() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement = agreementFactory.createAgreement(
            agreementFeeRecipient,
            ethCost,
            secDuration,
            feeSplitBps,
            newRoyaltyBps
        );
        factory.toggleAgreementForCollection(
            address(newAgreement),
            address(test721),
            true
        );
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Check the upfront fee was received
        assertEq(agreementFeeRecipient.balance, ethCost);

        // Check the Agreement has been applied, with the new bps
        (bool isInAgreement, uint96 pairRoyaltyBps) = factory.agreementForPair(
            address(pair)
        );
        assertEq(isInAgreement, true);
        assertEq(pairRoyaltyBps, newRoyaltyBps);

        // Check that the fee address is no longer the pool (i.e. a fee splitter has been deployed)
        require(
            pair.getFeeRecipient() != address(pair),
            "Splitter not deployed"
        );

        // Perform a buy for item #1
        (, , , uint256 inputAmount, ) = pair.getBuyNFTQuote(1);
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;
        pair.swapTokenForSpecificNFTs{
            value: this.modifyInputAmount(inputAmount)
        }(specificIdToBuy, inputAmount, address(this), false, address(this));

        uint256 royaltyBalance = getBalance(ROYALTY_RECEIVER);
        assertEq(royaltyBalance, calcRoyalty(inputAmount, newRoyaltyBps));

        // Perform a sell for item #1
        (, , , uint256 outputAmount, ) = pair.getSellNFTQuote(1);
        uint256[] memory specificIdToSell = new uint256[](1);
        specificIdToSell[0] = 1;
        pair.swapNFTsForToken(
            specificIdToSell,
            outputAmount,
            payable(address(this)),
            false,
            address(this)
        );
        uint256 secondRoyaltyPayment = getBalance(ROYALTY_RECEIVER) -
            royaltyBalance;
        assertEq(
            secondRoyaltyPayment,
            calcRoyalty(outputAmount, newRoyaltyBps)
        );
    }

    // A pair cannot enter a Standard Agreement if the Agreement is unauthorized
    function testFail_enterAgreementForPoolIfAgreementIsNotAuthHasNoEffect()
        public
    {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 10000; // 10% in bps
        StandardAgreement newAgreement = agreementFactory.createAgreement(
            agreementFeeRecipient,
            ethCost,
            secDuration,
            feeSplitBps,
            newRoyaltyBps
        );
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");
    }

    // A mock pair cannot enter a Standard Agreement
    function testFail_enterAgreementForMockPool() public {
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0.1 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement = agreementFactory.createAgreement(
            agreementFeeRecipient,
            ethCost,
            secDuration,
            feeSplitBps,
            newRoyaltyBps
        );
        factory.toggleAgreementForCollection(
            address(newAgreement),
            address(test721),
            true
        );
        mockPair.transferOwnership{value: ethCost}(address(newAgreement), "");
    }

    // Leaving after the expiry date succeeds
    function test_leaveAgreementAfterExpiry() public {

        // Set up basic Agreement
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement = agreementFactory.createAgreement(
            agreementFeeRecipient,
            ethCost,
            secDuration,
            feeSplitBps,
            newRoyaltyBps
        );
        factory.toggleAgreementForCollection(
            address(newAgreement),
            address(test721),
            true
        );

        // Opt into the Agreement
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Skip ahead in time
        skip(secDuration + 1);

        // Attempt to leave the Agreement
        newAgreement.reclaimPair(address(pair));

        // Check that the owner is now set back to caller
        assertEq(pair.owner(), address(this));
        // Prev fee recipient defaulted to the pair, so it should still be the pair
        assertEq(pair.getFeeRecipient(), address(pair)); 
        (bool isInAgreement,) = factory.agreementForPair(address(pair));
        assertEq(isInAgreement, false);
    }

    // Leaving after the expiry date succeeds
    function testFail_leaveAgreementAfterExpiryAsDiffCaller() public {

        // Set up basic Agreement
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement = agreementFactory.createAgreement(
            agreementFeeRecipient,
            ethCost,
            secDuration,
            feeSplitBps,
            newRoyaltyBps
        );
        factory.toggleAgreementForCollection(
            address(newAgreement),
            address(test721),
            true
        );

        // Opt into the Agreement
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Skip ahead in time
        skip(secDuration + 1);

        hoax(address(12321));

        // Attempt to leave the Agreement
        newAgreement.reclaimPair(address(pair));
    }

    // Leaving before the expiry date fails
    function testFail_leaveAgreementBeforeExpiry() public {

        // Set up basic Agreement
        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0 ether;
        uint64 secDuration = 100;
        uint64 feeSplitBps = 2;
        uint64 newRoyaltyBps = 1000; // 10% in bps
        StandardAgreement newAgreement = agreementFactory.createAgreement(
            agreementFeeRecipient,
            ethCost,
            secDuration,
            feeSplitBps,
            newRoyaltyBps
        );
        factory.toggleAgreementForCollection(
            address(newAgreement),
            address(test721),
            true
        );

        // Opt into the Agreement
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Attempt to leave the Agreement
        newAgreement.reclaimPair(address(pair));
    }

    // Splitter tests

    // A pair can enter a Standard Agreement if authorized
    function test_splitterHandlesSplits() public {
        // Set the trade fee recipient address
        address payable pairFeeRecipient = payable(address(1));
        pair.changeAssetRecipient(pairFeeRecipient);

        // Set trade fee to be 10%
        pair.changeFee(0.1 ether);

        address payable agreementFeeRecipient = payable(address(123));
        uint256 ethCost = 0 ether;
        uint64 secDuration = 1;
        uint64 feeSplitBps = 5000; // 50% split
        uint64 newRoyaltyBps = 0; // 0% in bps
        StandardAgreement newAgreement = agreementFactory.createAgreement(
            agreementFeeRecipient,
            ethCost,
            secDuration,
            feeSplitBps,
            newRoyaltyBps
        );
        factory.toggleAgreementForCollection(
            address(newAgreement),
            address(test721),
            true
        );
        pair.transferOwnership{value: ethCost}(address(newAgreement), "");

        // Check that the fee address is no longer the pool (i.e. a fee splitter has been deployed)
        require(
            pair.getFeeRecipient() != address(pair),
            "Splitter not deployed"
        );

        // Verify the Splitter has the correct variables
        assertEq(
            Splitter(pair.getFeeRecipient()).getParentAgreement(),
            address(newAgreement),
            "Incorrect parent"
        );
        assertEq(
            Splitter(pair.getFeeRecipient()).getPairAddressForSplitter(),
            address(pair),
            "Incorrect pair"
        );

        // Perform a buy for item #1
        (
            ,
            ,
            ,
            /* error*/
            /* new delta */
            /* new spot price*/
            uint256 inputAmount,
            uint256 tradeFee, // protocolFee

        ) = pair.bondingCurve().getBuyInfo(
                pair.spotPrice(),
                pair.delta(),
                1,
                pair.fee(),
                factory.protocolFeeMultiplier()
            );
        uint256[] memory specificIdToBuy = new uint256[](1);
        specificIdToBuy[0] = 1;
        pair.swapTokenForSpecificNFTs{
            value: this.modifyInputAmount(inputAmount)
        }(specificIdToBuy, inputAmount, address(this), false, address(this));

        // Ensure that 2x the trade fee went to the splitter
        address payable splitterAddress = pair.getFeeRecipient();
        uint256 splitterBalance = getBalance(splitterAddress);
        assertEq(splitterBalance, 2 * tradeFee);

        // Withdraw the tokens
        if (
            factory.isPair(address(pair), ILSSVMPairFactoryLike.PairVariant.ETH)
        ) {
            Splitter(splitterAddress).withdrawAllETH();
        } else {
            Splitter(splitterAddress).withdrawAllBaseQuoteTokens();
        }

        // Ensure that the Agreement-set fee recipient received the tokens
        uint256 agreementFeeRecipientBalance = getBalance(
            agreementFeeRecipient
        );
        assertEq(agreementFeeRecipientBalance, tradeFee);
        uint256 tradeFeeRecipientBalance = getBalance(pairFeeRecipient);
        assertEq(tradeFeeRecipientBalance, tradeFee);

        // Do two swaps in succession
        // Perform a buy for item #2 and #3
        (
            ,
            ,
            ,
            /* error*/
            /* new delta */
            /* new spot price*/
            inputAmount,
            tradeFee,

        ) = pair.bondingCurve().getBuyInfo( // protocolFee
            pair.spotPrice(),
            pair.delta(),
            2,
            pair.fee(),
            factory.protocolFeeMultiplier()
        );
        specificIdToBuy = new uint256[](2);
        specificIdToBuy[0] = 2;
        specificIdToBuy[1] = 3;
        pair.swapTokenForSpecificNFTs{
            value: this.modifyInputAmount(inputAmount)
        }(specificIdToBuy, inputAmount, address(this), false, address(this));

        // Ensure that 2x the trade fee went to the splitter
        splitterAddress = pair.getFeeRecipient();
        splitterBalance = getBalance(splitterAddress);
        assertEq(splitterBalance, 2 * tradeFee);
    }
}
