// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {LSSVMPair} from "./LSSVMPair.sol";
import {ILSSVMPairERC721} from "./erc721/ILSSVMPairERC721.sol";
import {LSSVMPairERC1155} from "./erc1155/LSSVMPairERC1155.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {CurveErrorCodes} from "./bonding-curves/CurveErrorCodes.sol";

contract VeryFastRouter {
    using SafeTransferLib for address payable;
    using SafeTransferLib for ERC20;

    ILSSVMPairFactoryLike public immutable factory;

    struct BuyOrderWithPartialFill {
        LSSVMPair pair;
        uint256[] nftIds;
        uint256 maxInputAmount;
        uint256 ethAmount;
        uint256 expectedSpotPrice;
        bool isERC721;
        uint256[] maxCostPerNumNFTs; // @dev This is zero-indexed, so maxCostPerNumNFTs[x] = max price we're willing to pay to buy x+1 NFTs
    }

    struct SellOrder {
        LSSVMPair pair;
        bool isETHSell;
        uint256[] nftIds;
        bytes propertyCheckParams;
        bool doPropertyCheck;
        uint256 expectedSpotPrice;
        uint256 minExpectedTokenOutput;
    }

    struct Order {
        BuyOrderWithPartialFill[] buyOrders;
        SellOrder[] sellOrders;
        address payable tokenRecipient;
        bool recycleETH;
    }

    constructor(ILSSVMPairFactoryLike _factory) {
        factory = _factory;
    }

    /* @dev Meant to be used as a client-side utility
     * Given a pair and a number of items to buy, calculate the max price paid for 1 up to numNFTs to buy
     */
    function getNFTQuoteForBuyOrderWithPartialFill(LSSVMPair pair, uint256 numNFTs)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory prices = new uint256[](numNFTs);
        uint128 spotPrice = pair.spotPrice();
        uint128 delta = pair.delta();
        uint256 fee = pair.fee();
        for (uint256 i; i < numNFTs; ++i) {
            uint256 price;
            (, spotPrice, delta, price,,) =
                pair.bondingCurve().getBuyInfo(spotPrice, delta, 1, fee, pair.factory().protocolFeeMultiplier());
            prices[i] = price;
        }
        uint256[] memory totalPrices = new uint256[](numNFTs);
        totalPrices[0] = prices[prices.length - 1];
        for (uint256 i = 1; i < numNFTs; ++i) {
            totalPrices[i] = totalPrices[i - 1] + prices[prices.length - 1 - i];
        }
        return totalPrices;
    }

    /* @dev Meant to be used as a client-side utility
     * Given a pair and a number of items to buy, calculate the max price paid for 1 up to numNFTs to buy
     */
    function getNFTQuoteForSellOrderWithPartialFill(LSSVMPair pair, uint256 numNFTs)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory prices = new uint256[](numNFTs);
        uint128 spotPrice = pair.spotPrice();
        uint128 delta = pair.delta();
        uint256 fee = pair.fee();
        for (uint256 i; i < numNFTs; ++i) {
            uint256 price;
            (, spotPrice, delta, price,,) =
                pair.bondingCurve().getSellInfo(spotPrice, delta, 1, fee, pair.factory().protocolFeeMultiplier());
            prices[i] = price;
        }
        uint256[] memory totalPrices = new uint256[](numNFTs);
        totalPrices[0] = prices[prices.length - 1];
        for (uint256 i = 1; i < numNFTs; ++i) {
            totalPrices[i] = totalPrices[i - 1] + prices[prices.length - 1 - i];
        }
        return totalPrices;
    }

    /**
     * @dev Performs a batch of sells and buys, avoids performing swaps where the price is beyond
     * Handles selling NFTs for tokens or ETH
     * Handles buying NFTs with tokens or ETH,
     */
    function swap(Order calldata swapOrder) external payable {
        uint256 ethAmount = msg.value;

        // Go through each sell order
        for (uint256 i; i < swapOrder.sellOrders.length; ++i) {
            SellOrder calldata order = swapOrder.sellOrders[i];
            LSSVMPair pair = order.pair;

            // If the price seen is what we expect it to be...
            if (pair.spotPrice() == order.expectedSpotPrice) {
                // If the pair is an ETH pair and we opt into recycling ETH, add the output to our total accrued
                if (order.isETHSell && swapOrder.recycleETH) {
                    uint256 outputAmount;

                    // Pass in params for property checking if needed
                    // Then do the swap with the same minExpectedTokenOutput amount
                    if (order.doPropertyCheck) {
                        outputAmount = ILSSVMPairERC721(address(pair)).swapNFTsForToken(
                            order.nftIds,
                            order.minExpectedTokenOutput,
                            payable(address(this)),
                            true,
                            msg.sender,
                            order.propertyCheckParams
                        );
                    } else {
                        outputAmount = pair.swapNFTsForToken(
                            order.nftIds, order.minExpectedTokenOutput, payable(address(this)), true, msg.sender
                        );
                    }

                    // Accumulate ETH amount
                    ethAmount += outputAmount;
                }
                // Otherwise, all tokens or ETH received from the sale go to the swap recipient
                else {
                    // Pass in params for property checking if needed
                    // Then do the swap with the same minExpectedTokenOutput amount
                    if (order.doPropertyCheck) {
                        ILSSVMPairERC721(address(pair)).swapNFTsForToken(
                            order.nftIds,
                            order.minExpectedTokenOutput,
                            swapOrder.tokenRecipient,
                            true,
                            msg.sender,
                            order.propertyCheckParams
                        );
                    } else {
                        pair.swapNFTsForToken(
                            order.nftIds, order.minExpectedTokenOutput, swapOrder.tokenRecipient, true, msg.sender
                        );
                    }
                }
            }
        }

        // Get protocol fee if we are doing buys, to reduce gas on the _findMaxFillableAmtForBuy call
        uint256 protocolFeeMultiplier;
        if (swapOrder.buyOrders.length > 0) {
            protocolFeeMultiplier = swapOrder.buyOrders[0].pair.factory().protocolFeeMultiplier();
        }

        // Go through each buy order
        for (uint256 i; i < swapOrder.buyOrders.length; ++i) {
            BuyOrderWithPartialFill calldata order = swapOrder.buyOrders[i];
            LSSVMPair pair = order.pair;

            // If the spot price seen is what we expect it to be...
            if (pair.spotPrice() == order.expectedSpotPrice) {
                // Then do a direct swap for all items we want
                uint256 inputAmount = pair.swapTokenForSpecificNFTs{value: order.ethAmount}(
                    order.nftIds, order.maxInputAmount, swapOrder.tokenRecipient, true, msg.sender
                );

                // Deduct ETH amount if it's an ETH swap
                if (order.ethAmount > 0) {
                    ethAmount -= inputAmount;
                }
            }
            // Otherwise, we need to do some partial fill calculations first
            else {
                (uint256 numItemsToFill, uint256 priceToFillAt) =
                    _findMaxFillableAmtForBuy(pair, order.nftIds.length, order.maxCostPerNumNFTs, protocolFeeMultiplier);

                // Continue if we can fill at least 1 item
                if (numItemsToFill > 0) {
                    // Set ETH amount to send (is 0 if it's an ERC20 swap)
                    uint256 ethToSendForBuy;
                    if (order.ethAmount > 0) {
                        ethToSendForBuy = priceToFillAt;
                    }

                    uint256 inputAmount;

                    // If ERC721 swap
                    if (order.isERC721) {
                        // Get list of actually valid ids to buy
                        uint256[] memory availableIds = _findAvailableIds(pair, numItemsToFill, order.nftIds);

                        inputAmount = pair.swapTokenForSpecificNFTs{value: ethToSendForBuy}(
                            availableIds, priceToFillAt, swapOrder.tokenRecipient, true, msg.sender
                        );
                    }
                    // If ERC1155 swap
                    else {
                        // The amount to buy is the min(numItemsToFill, erc1155.balanceOf(pair))
                        {
                            address pairAddress = address(pair);
                            uint256 availableNFTs =
                                IERC1155(pair.nft()).balanceOf(pairAddress, LSSVMPairERC1155(pairAddress).nftId());
                            numItemsToFill = numItemsToFill < availableNFTs ? numItemsToFill : availableNFTs;
                        }
                        uint256[] memory erc1155SwapAmount = new uint256[](1);
                        erc1155SwapAmount[0] = numItemsToFill;

                        // Do the 1155 swap, with the modified amount to buy
                        inputAmount = pair.swapTokenForSpecificNFTs{value: ethToSendForBuy}(
                            erc1155SwapAmount, priceToFillAt, swapOrder.tokenRecipient, true, msg.sender
                        );
                    }

                    // Deduct ETH amount if it's an ETH swap
                    if (order.ethAmount > 0) {
                        ethAmount -= inputAmount;
                    }
                }
            }
        }

        // Send excess ETH back to token recipient
        if (ethAmount > 0) {
            payable(swapOrder.tokenRecipient).safeTransferETH(ethAmount);
        }
    }

    receive() external payable {}

    /**
     * Internal helper functions
     */

    /**
     *   @dev Performs a binary search to find the largest value where maxCostPerNumNFTs is still greater than
     *   the pair's bonding curve's getBuyInfo() value.
     *   @param pair The pair to calculate partial fill values for
     *   @param maxNumNFTs The maximum number of NFTs to fill / get a quote for
     *   @param maxCostPerNumNFTs The user's specified maximum price to pay for filling a number of NFTs
     *   @dev Note that maxPricesPerNumNFTs is 0-indexed
     */
    function _findMaxFillableAmtForBuy(
        LSSVMPair pair,
        uint256 maxNumNFTs,
        uint256[] memory maxCostPerNumNFTs,
        uint256 protocolFeeMultiplier
    ) internal view returns (uint256 numItemsToFill, uint256 priceToFillAt) {
        // Set start and end indices
        uint256 start = 1;
        uint256 end = maxNumNFTs;

        // Cache current pair values
        uint128 spotPrice = pair.spotPrice();
        uint128 delta = pair.delta();
        uint256 feeMultiplier = pair.fee();

        // Perform binary search
        while (start <= end) {
            // uint256 numItems = (start + end)/2; (but we hard-code it below to avoid stack too deep)

            // We check the price to buy index + 1
            (
                CurveErrorCodes.Error error,
                /* newSpotPrice */
                ,
                /* newDelta */
                ,
                uint256 currentCost,
                /* tradeFee */
                ,
                /* protocolFee */
            ) = pair.bondingCurve().getBuyInfo(
                spotPrice, delta, (start + end) / 2, feeMultiplier, protocolFeeMultiplier
            );

            // If the bonding curve has a math error, or
            // If the current price is too expensive relative to our max cost,
            // then we recurse on the left half (i.e. less items)
            if (
                error != CurveErrorCodes.Error.OK || currentCost > maxCostPerNumNFTs[(start + end) / 2 - 1] /* this is the max cost we are willing to pay, zero-indexed */
            ) {
                end = (start + end) / 2 - 1;
            }
            // Otherwise, we recurse on the right half (i.e. more items)
            else {
                start = (start + end) / 2 + 1;
                numItemsToFill = (start + end) / 2;
                priceToFillAt = currentCost;
            }
        }
    }

    /**
     *   @dev Performs a binary search to find the largest value where maxOutputPerNumNFTs is still less than
     *   the pair's bonding curve's getSellInfo() value.
     *   @param pair The pair to calculate partial fill values for
     *   @param maxNumNFTs The maximum number of NFTs to fill / get a quote for
     *   @param maxOutputPerNumNFTs The user's specified maximum price to pay for filling a number of NFTs
     *   @dev Note that maxOutputPerNumNFTs is 0-indexed
     */
    function _findMaxFillableAmtForSell(
        LSSVMPair pair,
        uint256 maxNumNFTs,
        uint256[] memory maxOutputPerNumNFTs,
        uint256 protocolFeeMultiplier
    ) internal view returns (uint256 numItemsToFill, uint256 priceToFillAt) {
        // Set start and end indices
        uint256 start = 1;
        uint256 end = maxNumNFTs;

        // Cache current pair values
        uint128 spotPrice = pair.spotPrice();
        uint128 delta = pair.delta();
        uint256 feeMultiplier = pair.fee();

        // Get current pair balance
        uint256 tokenBalance;

        // TODO: implement
    }

    /**
     *   @dev Checks ownership of all desired NFT IDs to see which ones are still fillable
     *   @param pair The pair to check for ownership
     *   @param maxIdsNeeded The maximum amount of NFTs we want, guaranteed to be up to potentialIds.length, but could be less
     *   @param potentialIds The possible NFT IDs that the pair could own
     *   @return idsToBuy Actual NFT IDs owned by the pair, guaranteed to be up to maxIdsNeeded length, but could be less
     */
    function _findAvailableIds(LSSVMPair pair, uint256 maxIdsNeeded, uint256[] memory potentialIds)
        internal
        view
        returns (uint256[] memory idsToBuy)
    {
        IERC721 nft = IERC721(pair.nft());
        uint256[] memory idsThatExist = new uint256[](maxIdsNeeded);
        uint256 numIdsFound = 0;

        // Go through each potential ID, and check to see if it's still owned by the pair
        // If it is, record the ID
        // Return early if we found all the IDs we need
        for (uint256 i; i < maxIdsNeeded; ++i) {
            if (nft.ownerOf(potentialIds[i]) == address(pair)) {
                idsThatExist[numIdsFound] = potentialIds[i];
                numIdsFound += 1;
                if (numIdsFound == maxIdsNeeded) {
                    return idsThatExist;
                }
            }
        }
        // Otherwise, we didn't find enough IDs, so we need to return a subset
        if (numIdsFound < maxIdsNeeded) {
            uint256[] memory allIdsFound = new uint256[](numIdsFound);
            for (uint256 i; i < numIdsFound; ++i) {
                allIdsFound[i] = idsThatExist[i];
            }
            return allIdsFound;
        }
    }

    /**
     * Restricted functions
     */

    /**
     * @dev Allows an ERC20 pair contract to transfer ERC20 tokens directly from
     *     the sender, in order to minimize the number of token transfers. Only callable by an ERC20 pair.
     *     @param token The ERC20 token to transfer
     *     @param from The address to transfer tokens from
     *     @param to The address to transfer tokens to
     *     @param amount The amount of tokens to transfer
     */
    function pairTransferERC20From(ERC20 token, address from, address to, uint256 amount) external {
        // verify caller is a trusted pair contract
        require(factory.isValidPair(msg.sender), "Not pair");

        // verify caller is an ERC20 pair
        require(factory.getPairTokenType(msg.sender) == ILSSVMPairFactoryLike.PairTokenType.ERC20, "Not ERC20 pair");

        // transfer tokens to pair
        token.safeTransferFrom(from, to, amount);
    }

    /**
     * @dev Allows a pair contract to transfer ERC721 NFTs directly from
     *     the sender, in order to minimize the number of token transfers. Only callable by a pair.
     *     @param nft The ERC721 NFT to transfer
     *     @param from The address to transfer tokens from
     *     @param to The address to transfer tokens to
     *     @param id The ID of the NFT to transfer
     */
    function pairTransferNFTFrom(IERC721 nft, address from, address to, uint256 id) external {
        // verify caller is a trusted pair contract
        require(
            factory.isValidPair(msg.sender)
                && factory.getPairNFTType(msg.sender) == ILSSVMPairFactoryLike.PairNFTType.ERC721,
            "Invalid ERC721 pair"
        );

        // transfer NFTs to pair
        nft.transferFrom(from, to, id);
    }

    /**
     * @dev Allows a pair contract to transfer ERC1155 NFTs directly from
     *     the sender, in order to minimize the number of token transfers. Only callable by a pair.
     *     @param nft The ERC1155 NFT to transfer
     *     @param from The address to transfer tokens from
     *     @param to The address to transfer tokens to
     *     @param ids The IDs of the NFT to transfer
     *     @param amounts The amount of each ID to transfer
     */
    function pairTransferERC1155From(
        IERC1155 nft,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external {
        // verify caller is a trusted pair contract
        require(
            factory.isValidPair(msg.sender)
                && factory.getPairNFTType(msg.sender) == ILSSVMPairFactoryLike.PairNFTType.ERC1155,
            "Invalid ERC1155 pair"
        );

        // transfer NFTs to pair
        nft.safeBatchTransferFrom(from, to, ids, amounts, bytes(""));
    }
}
