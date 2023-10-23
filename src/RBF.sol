// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LSSVMPair} from "./LSSVMPair.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {IOwnershipTransferReceiver} from "./lib/IOwnershipTransferReceiver.sol";
import {OwnableWithTransferCallback} from "./lib/OwnableWithTransferCallback.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract RBF is IOwnershipTransferReceiver, ERC721Holder, ReentrancyGuard {
    using SafeTransferLib for address payable;

    uint8 private constant COLLATERAL_NUMER = 11;
    uint8 private constant COLLATERAL_DENOM = 10;

    uint64 private constant SECONDS_PER_DAY = 86400;
    uint64 private constant INTEREST_PER_DAY_NUMER = 1;
    uint64 private constant INTEREST_PER_DAY_DENOM = 1000;
    uint64 private constant LIQ_INCENTIVE_NUMER = 1;
    uint64 private constant LIQ_INCENTIVE_DENOM = 100;

    uint256 private constant MIN_INTEREST = 0.01 ether;
    uint256 private constant MAX_LOAN_DURATION = 7 days;
    uint256 private constant MIN_PRICE_MULTIPLIER = 0.01 ether;
    uint256 private constant DELAY_BETWEEN_BORROWS_MULTIPLIER = 10 seconds;

    struct LoanMetadata {
        address prevOwner;
        uint32 lastBorrowTime;
        uint24 minPrice;
        uint24 delayBetweenBorrows;
        uint16 maxAmountPerBorrow;
    }

    struct LoanInfo {
        address pairDebtor;
        uint64 numNFTsBorrowed;
        uint32 loanStartTime;
        uint128 collateralAmount;
    }

    mapping(address => LoanMetadata) public pairData;
    mapping(address => LoanInfo) public openLoanForBorrower;

    ILSSVMPairFactoryLike immutable factory;

    constructor(ILSSVMPairFactoryLike _factory) {
        factory = _factory;
    }

    function borrow(
        address pairAddress,
        uint256[] calldata idsToBorrow,
        address pairToSwapWith,
        uint256 minOutputAmount
    ) external payable {
        // Only 1 loan out at a time
        require(
            openLoanForBorrower[msg.sender].pairDebtor == address(0),
            "Outstanding loan"
        );

        LoanMetadata memory loanMetadata = pairData[pairAddress];

        // Rate limit checks
        require(
            idsToBorrow.length <= loanMetadata.maxAmountPerBorrow,
            "Too many"
        );
        require(
            block.timestamp >=
                loanMetadata.lastBorrowTime +
                    (loanMetadata.delayBetweenBorrows *
                        DELAY_BETWEEN_BORROWS_MULTIPLIER),
            "Too soon"
        );

        // Only for valid ERC721 ETH pairs
        require(factory.isValidPair(pairAddress), "Invalid pair");
        require(
            LSSVMPair(pairAddress).pairVariant() ==
                ILSSVMPairFactoryLike.PairVariant.ERC721_ETH,
            "Invalid pair type"
        );

        // Price checks
        (, , , uint256 bondingCurvePrice, , ) = LSSVMPair(pairAddress)
            .getBuyNFTQuote(idsToBorrow[0], 1);
        uint256 minLoanPrice = MIN_PRICE_MULTIPLIER * loanMetadata.minPrice;
        if (bondingCurvePrice > minLoanPrice) {
            minLoanPrice = bondingCurvePrice;
        }

        // Withdraw NFTs from pair
        IERC721 nft = IERC721(LSSVMPair(pairAddress).nft());
        LSSVMPair(pairAddress).withdrawERC721(nft, idsToBorrow);

        // Collateral calculation (scale up by safety factor)
        uint256 collateralAmount = _calculateCollateralAmount(
            minLoanPrice * idsToBorrow.length
        );

        // If target pool to swap with is address(0), do the collateral check directly
        if (pairToSwapWith == address(0)) {
            require(msg.value == collateralAmount, "Insufficient ETH");

            // Transfer NFTs to caller directly
            for (uint i; i < idsToBorrow.length; ) {
                nft.transferFrom(address(this), msg.sender, idsToBorrow[i]);
                unchecked {
                    ++i;
                }
            }
        }
        // Otherwise, do swap with validation
        else {
            // Only for valid ERC721 ETH pairs
            require(factory.isValidPair(pairToSwapWith), "Invalid pair");
            require(
                LSSVMPair(pairToSwapWith).pairVariant() ==
                    ILSSVMPairFactoryLike.PairVariant.ERC721_ETH,
                "Invalid pair type"
            );

            uint256 collateralDiff = collateralAmount - msg.value;
            uint256 preSwapBalance = address(this).balance;

            // Swap directly with the pool
            nft.setApprovalForAll(pairToSwapWith, true);
            LSSVMPair(pairToSwapWith).swapNFTsForToken(
                idsToBorrow,
                minOutputAmount,
                payable(address(this)),
                false,
                address(0)
            );

            require(
                address(this).balance - preSwapBalance >= collateralDiff,
                "Not enough"
            );
            nft.setApprovalForAll(pairToSwapWith, false);
        }

        // Update the last borrow time
        loanMetadata.lastBorrowTime = uint32(block.timestamp);
        pairData[pairAddress] = loanMetadata;

        // Store the loan values
        openLoanForBorrower[msg.sender] = LoanInfo({
            pairDebtor: pairAddress,
            numNFTsBorrowed: uint64(idsToBorrow.length),
            loanStartTime: uint32(block.timestamp),
            collateralAmount: uint128(collateralAmount)
        });
    }

    function repay(
        uint256[] calldata idsToRepay
    ) external payable nonReentrant {
        require(idsToRepay.length > 0, "Empty");

        // Get loan data
        LoanInfo memory loanInfo = openLoanForBorrower[msg.sender];

        // Delete loan data
        delete openLoanForBorrower[msg.sender];

        // Calculate interest
        // Interest = min interest * amount + interest rate * amount time
        uint256 interestToPay = (MIN_INTEREST * idsToRepay.length) +
            (loanInfo.collateralAmount *
                (block.timestamp - loanInfo.loanStartTime) *
                INTEREST_PER_DAY_NUMER) /
            INTEREST_PER_DAY_DENOM /
            SECONDS_PER_DAY;

        // Transfer from interest from caller to pair
        require(msg.value >= interestToPay, "Too little");
        payable(loanInfo.pairDebtor).safeTransferETH(msg.value);

        // Transfer collateral from RBF to caller
        payable(msg.sender).safeTransferETH(loanInfo.collateralAmount);

        // Transfer NFTs from caller to pair
        IERC721 nft = IERC721(LSSVMPair(loanInfo.pairDebtor).nft());
        for (uint i; i < loanInfo.numNFTsBorrowed; ) {
            nft.transferFrom(msg.sender, loanInfo.pairDebtor, idsToRepay[i]);
            unchecked {
                ++i;
            }
        }
    }

    function liquidate(address loanOriginator) external payable nonReentrant {
        LoanInfo memory loanInfo = openLoanForBorrower[loanOriginator];

        // Can only liquidate after loan is expired
        require(
            block.timestamp > loanInfo.loanStartTime + MAX_LOAN_DURATION,
            "Not yet"
        );

        // Delete loan data
        delete openLoanForBorrower[loanOriginator];

        // Calculate split between liquidator and pool
        uint256 liqIncentive = (loanInfo.collateralAmount *
            LIQ_INCENTIVE_NUMER) / LIQ_INCENTIVE_DENOM;
        uint256 poolCollateralAmount = loanInfo.collateralAmount - liqIncentive;

        // Send collateral to pool
        payable(loanInfo.pairDebtor).safeTransferETH(poolCollateralAmount);

        // Send liq incentive to caller
        payable(msg.sender).safeTransferETH(liqIncentive);
    }

    function onOwnershipTransferred(
        address oldOwner,
        bytes memory data
    ) external payable {
        // Only for valid ERC721 ETH pairs
        require(factory.isValidPair(msg.sender), "Invalid pair");
        require(
            LSSVMPair(msg.sender).pairVariant() ==
                ILSSVMPairFactoryLike.PairVariant.ERC721_ETH,
            "Invalid pair type"
        );
        (
            uint24 minPrice,
            uint16 delayBetweenBorrows,
            uint16 maxAmountPerBorrow
        ) = abi.decode(data, (uint24, uint16, uint16));
        pairData[msg.sender] = LoanMetadata({
            prevOwner: oldOwner,
            lastBorrowTime: 0,
            minPrice: minPrice,
            delayBetweenBorrows: delayBetweenBorrows,
            maxAmountPerBorrow: maxAmountPerBorrow
        });
    }

    function reclaimPairs(address[] calldata pairAddresses) external payable {
        for (uint i; i < pairAddresses.length; ) {
            LoanMetadata memory loanMetadata = pairData[pairAddresses[i]];
            require(loanMetadata.prevOwner == msg.sender, "Not owner");
            OwnableWithTransferCallback(pairAddresses[i]).transferOwnership(
                msg.sender,
                ""
            );
            unchecked {
                ++i;
            }
        }
    }

    function _calculateCollateralAmount(
        uint256 c
    ) private pure returns (uint256) {
        return (c * COLLATERAL_NUMER) / COLLATERAL_DENOM;
    }
    
    // Receive ETH
    receive() external payable {}
}
