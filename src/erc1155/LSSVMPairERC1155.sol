// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {LSSVMPair} from "../LSSVMPair.sol";
import {LSSVMRouter} from "../LSSVMRouter.sol";
import {ICurve} from "../bonding-curves/ICurve.sol";
import {ILSSVMPairFactoryLike} from "../ILSSVMPairFactoryLike.sol";

/// @title LSSVMPairERC1155
/// @author boredGenius and 0xmons
/// @notice An NFT/Token pair for an ERC1155 NFT where NFTs with the same ID are considered fungible.
abstract contract LSSVMPairERC1155 is LSSVMPair {
    /**
     * External state-changing functions
     */

    /**
     * @notice Sends token to the pair in exchange for any `numNFTs` NFTs
     *     @dev To compute the amount of token to send, call bondingCurve.getBuyInfo.
     *     This swap function is meant for users who are ID agnostic
     *     @param numNFTs The number of NFTs to purchase
     *     @param maxExpectedTokenInput The maximum acceptable cost from the sender. If the actual
     *     amount is greater than this value, the transaction will be reverted.
     *     @param nftRecipient The recipient of the NFTs
     *     @param isRouter True if calling from LSSVMRouter, false otherwise. Not used for
     *     ETH pairs.
     *     @param routerCaller If isRouter is true, ERC20 tokens will be transferred from this address. Not used for
     *     ETH pairs.
     *     @return inputAmount The amount of token used for purchase
     */
    function swapTokenForSpecificNFTs(
        uint256[] calldata numNFTs,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool isRouter,
        address routerCaller
    ) external payable virtual override returns (uint256 inputAmount) {
        // Store locally to remove extra calls
        ILSSVMPairFactoryLike _factory = factory();

        _factory.openLock();

        ICurve _bondingCurve = bondingCurve();
        IERC1155 _nft = IERC1155(nft());

        // Input validation
        {
            PoolType _poolType = poolType();
            require(_poolType == PoolType.NFT || _poolType == PoolType.TRADE, "Wrong Pool type");
            require(numNFTs.length == 1 && numNFTs[0] != 0, "Must swap > 0 NFTs");
        }

        // Call bonding curve for pricing information
        uint256 tradeFee;
        uint256 protocolFee;
        (tradeFee, protocolFee, inputAmount) =
            _calculateBuyInfoAndUpdatePoolParams(numNFTs[0], maxExpectedTokenInput, _bondingCurve, _factory);

        _pullTokenInputAndPayProtocolFee(
            nftId(), inputAmount, 2 * tradeFee, isRouter, routerCaller, _factory, protocolFee
        );

        _sendAnyNFTsToRecipient(_nft, nftRecipient, numNFTs[0]);

        _refundTokenToSender(inputAmount);

        _factory.closeLock();

        emit SwapNFTOutPair(inputAmount, numNFTs[0]);
    }

    /**
     * @notice Sends a set of NFTs to the pair in exchange for token
     *     @dev To compute the amount of token to that will be received, call bondingCurve.getSellInfo.
     *     @param numNFTs The number of NFTs to swap
     *     @param minExpectedTokenOutput The minimum acceptable token received by the sender. If the actual
     *     amount is less than this value, the transaction will be reverted.
     *     @param tokenRecipient The recipient of the token output
     *     @param isRouter True if calling from LSSVMRouter, false otherwise. Not used for
     *     ETH pairs.
     *     @param routerCaller If isRouter is true, ERC20 tokens will be transferred from this address. Not used for
     *     ETH pairs.
     *     @return outputAmount The amount of token received
     */
    function swapNFTsForToken(
        uint256[] calldata numNFTs, // @dev this is a bit hacky, to allow for better interop w/ other pair interfaces
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bool isRouter,
        address routerCaller
    ) external virtual override returns (uint256 outputAmount) {
        // Store locally to remove extra calls
        ILSSVMPairFactoryLike _factory = factory();

        _factory.openLock();

        ICurve _bondingCurve = bondingCurve();

        // Input validation
        {
            PoolType _poolType = poolType();
            require(_poolType == PoolType.TOKEN || _poolType == PoolType.TRADE, "Wrong Pool type");
            require(numNFTs.length == 1 && numNFTs[0] != 0, "Must swap > 0 NFTs");
        }

        // Call bonding curve for pricing information
        uint256 protocolFee;
        (protocolFee, outputAmount) = _calculateSellInfoAndUpdatePoolParams(numNFTs[0], _bondingCurve, _factory);

        // Compute royalties
        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 royaltyTotal) =
            _calculateRoyalties(nftId(), outputAmount);

        // Deduct royalties from outputAmount
        unchecked {
            // Safe because we already require outputAmount >= royaltyTotal in calculateRoyalties()
            outputAmount -= royaltyTotal;
        }

        require(outputAmount >= minExpectedTokenOutput, "Out too few tokens");

        _takeNFTsFromSender(IERC1155(nft()), numNFTs[0], _factory, isRouter, routerCaller);

        _sendTokenOutput(tokenRecipient, outputAmount);

        for (uint256 i; i < royaltyRecipients.length;) {
            _sendTokenOutput(royaltyRecipients[i], royaltyAmounts[i]);
            unchecked {
                ++i;
            }
        }

        _sendTokenOutput(payable(address(_factory)), protocolFee);

        _factory.closeLock();

        emit SwapNFTInPair(outputAmount, numNFTs[0]);
    }

    /**
     * View functions
     */

    /**
     * @notice Returns the ERC-1155 NFT ID this pool uses
     */
    function nftId() public pure returns (uint256 id) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            id := calldataload(add(sub(calldatasize(), paramsLength), 61))
        }
    }

    /**
     * Internal functions
     */

    /**
     * @notice Sends some number of NFTs to a recipient address
     *     @dev Even though we specify the NFT address here, this internal function is only
     *     used to send NFTs associated with this specific pool.
     *     @param _nft The address of the NFT to send
     *     @param nftRecipient The receiving address for the NFTs
     *     @param numNFTs The number of NFTs to send
     */
    function _sendAnyNFTsToRecipient(IERC1155 _nft, address nftRecipient, uint256 numNFTs) internal virtual {
        _nft.safeTransferFrom(address(this), nftRecipient, nftId(), numNFTs, bytes(""));
    }

    /**
     * @notice Takes NFTs from the caller and sends them into the pair's asset recipient
     *     @dev This is used by the LSSVMPair's swapNFTForToken function.
     *     @param _nft The NFT collection to take from
     *     @param numNFTs The number of NFTs to take
     *     @param isRouter Whether or not to use the router pull flow
     *     @param routerCaller If the caller is a router, passes in which address to pull from (i.e. the router's caller)
     */
    function _takeNFTsFromSender(
        IERC1155 _nft,
        uint256 numNFTs,
        ILSSVMPairFactoryLike factory,
        bool isRouter,
        address routerCaller
    ) internal virtual {
        address _assetRecipient = getAssetRecipient();

        if (isRouter) {
            // Verify if router is allowed
            LSSVMRouter router = LSSVMRouter(payable(msg.sender));
            (bool routerAllowed,) = factory.routerStatus(router);
            require(routerAllowed, "Not router");

            uint256 _nftId = nftId();
            uint256 beforeBalance = _nft.balanceOf(_assetRecipient, _nftId);
            uint256[] memory ids = new uint256[](1);
            ids[0] = _nftId;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = numNFTs;
            router.pairTransferERC1155From(_nft, routerCaller, _assetRecipient, ids, amounts);
            require((_nft.balanceOf(_assetRecipient, _nftId) - beforeBalance) == numNFTs, "NFTs not transferred");
        } else {
            // Pull NFTs directly from sender
            _nft.safeTransferFrom(msg.sender, _assetRecipient, nftId(), numNFTs, bytes(""));
        }
    }

    /**
     * Owner functions
     */

    /**
     * @notice Rescues a specified set of NFTs owned by the pair to the owner address. Only callable by the owner.
     *     @param a The NFT to transfer
     *     @param nftIds The list of IDs of the NFTs to send to the owner
     */
    function withdrawERC721(IERC721 a, uint256[] calldata nftIds) external virtual override onlyOwner {
        uint256 numNFTs = nftIds.length;
        for (uint256 i; i < numNFTs;) {
            a.safeTransferFrom(address(this), msg.sender, nftIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Transfers ERC1155 tokens from the pair to the owner. Only callable by the owner.
     *     @param a The NFT to transfer
     *     @param ids The NFT ids to transfer
     *     @param amounts The amounts of each id to transfer
     */
    function withdrawERC1155(IERC1155 a, uint256[] calldata ids, uint256[] calldata amounts)
        external
        virtual
        override
        onlyOwner
    {
        if (a == IERC1155(nft())) {
            // check if we need to emit an event for withdrawing the NFT this pool is trading
            uint256 _nftId = nftId();
            uint256 numNFTs = ids.length;
            uint256 numPairNFTsWithdrawn;
            for (uint256 i; i < numNFTs;) {
                if (ids[i] == _nftId) {
                    numPairNFTsWithdrawn += amounts[i];
                }
                unchecked {
                    ++i;
                }
            }

            if (numPairNFTsWithdrawn != 0) {
                // only emit for the pair's NFT
                emit NFTWithdrawal(numPairNFTsWithdrawn);
            }
        }

        a.safeBatchTransferFrom(address(this), msg.sender, ids, amounts, bytes(""));
    }
}
