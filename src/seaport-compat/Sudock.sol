// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20Interface, ERC721Interface} from "./seaport/AbridgedTokenInterfaces.sol";
import {ContractOffererInterface} from "./seaport/ContractOffererInterface.sol";
import {ItemType} from "./seaport/ConsiderationEnums.sol";
import {SpentItem, ReceivedItem, InventoryUpdate} from "./seaport/ConsiderationStructs.sol";

import {IOwnershipTransferReceiver} from "../lib/IOwnershipTransferReceiver.sol";
import {ILSSVMPair} from "../ILSSVMPair.sol";
import {ILSSVMPairFactoryLike} from "../ILSSVMPairFactoryLike.sol";
import {CurveErrorCodes} from "../bonding-curves/CurveErrorCodes.sol";
import {OwnableWithTransferCallback} from "../lib/OwnableWithTransferCallback.sol";

contract Sudock is IOwnershipTransferReceiver, ContractOffererInterface {
    error OnlySeaport();
    error OnlyERC20Pair();
    error OnlyPrevPairOwner();
    error InvalidOwnershipChange();
    error CurveError();
    error NotImplemented();
    error InvalidItemType();
    error InvalidToken();
    error InvalidTokenId(uint256 id);

    address immutable _SEAPORT;
    ILSSVMPairFactoryLike immutable pairFactory;

    constructor(address seaport, ILSSVMPairFactoryLike _pairFactory) {
        _SEAPORT = seaport;
        pairFactory = _pairFactory;
    }

    mapping(address => address) prevOwner;

    function onOwnershipTransferred(address _prevOwner, bytes memory)
        public
        payable
    {
        prevOwner[msg.sender] = _prevOwner;

        // Approve Seaport to spend tokens that are held by Sudock
        (ILSSVMPair(msg.sender).nft()).setApprovalForAll(_SEAPORT, true);
        (ILSSVMPair(msg.sender).token()).approve(_SEAPORT, type(uint256).max);
    }

    function multicall(
        ILSSVMPair pair,
        bytes[] calldata calls,
        bool revertOnFail
    ) external {
        if (msg.sender != prevOwner[address(pair)]) {
            revert OnlyPrevPairOwner();
        }
        pair.multicall(calls, revertOnFail);
        // @dev: Ownership can't change during this call, the multicall guarantees it
    }

    function undock(ILSSVMPair pair) external {
        if (msg.sender != prevOwner[address(pair)]) {
            revert OnlyPrevPairOwner();
        }
        OwnableWithTransferCallback(address(pair)).transferOwnership(msg.sender, "");
    }

    function generateOrder(
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata data
    )
        external
        override
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        // only Seaport may call this function
        if (msg.sender != _SEAPORT) {
            revert OnlySeaport();
        }

        address pairAddress = abi.decode(data, (address));

        if (
            !pairFactory.isPair(
                pairAddress,
                ILSSVMPairFactoryLike.PairVariant.ERC20
            )
        ) {
            revert OnlyERC20Pair();
        }

        // if true, this offerer is spending NFTs and receiving ERC20
        uint256 newSpotPrice;
        uint256 newDelta;
        bool withdrawNFTsFromPoolToSudock;
        uint256 tokensToWithdraw;
        uint256[] memory nftIdsToWithdraw;
        (
            offer,
            consideration,
            newSpotPrice,
            newDelta,
            withdrawNFTsFromPoolToSudock,
            tokensToWithdraw,
            nftIdsToWithdraw
        ) = _generateOfferAndConsideration(
            minimumReceived,
            maximumSpent,
            pairAddress
        );
        ILSSVMPair pair = ILSSVMPair(pairAddress);

        // Withdraw relevant tokens, used by Seaport for spending
        if (withdrawNFTsFromPoolToSudock) {
            pair.withdrawERC721(pair.nft(), nftIdsToWithdraw);
        } else {
            pair.withdrawERC20(pair.token(), tokensToWithdraw);
        }

        // Update spot price and delta by using underlying bonding curve
        pair.changeSpotPrice(uint128(newSpotPrice));
        pair.changeDelta(uint128(newDelta));
    }

    function _generateOfferAndConsideration(
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        address pairAddress
    )
        internal
        view
        returns (
            SpentItem[] memory offer,
            ReceivedItem[] memory consideration,
            uint256 newSpotPrice,
            uint256 newDelta,
            bool withdrawNFTsFromPoolToSudock,
            uint256 tokensToWithdraw,
            uint256[] memory nftIdsToWithdraw
        )
    {
        ILSSVMPair pair = ILSSVMPair(pairAddress);

        // validate that all tokens in each set are "homogenous" (ERC20 or ERC721/_WITH_CRITERIA)
        _validateSpentItems(pair, minimumReceived, true);
        _validateSpentItems(pair, maximumSpent, false);

        // if fulfiller is spending ERC20 tokens, calculate how much is needed for the number of tokens specified
        // in minimumReceived
        if (maximumSpent[0].itemType == ItemType.ERC20) {
            CurveErrorCodes.Error errorCode;
            uint256 outputAmount;
            (errorCode, newSpotPrice, newDelta, outputAmount, ) = pair
                .getBuyNFTQuote(minimumReceived.length);
            if (errorCode != CurveErrorCodes.Error.OK) {
                revert CurveError();
            }
            consideration = new ReceivedItem[](1);
            consideration[0] = ReceivedItem({
                itemType: ItemType.ERC20,
                token: address(pair.token()),
                identifier: 0,
                amount: outputAmount,
                recipient: payable(address(pair))
            });
            offer = minimumReceived;
            withdrawNFTsFromPoolToSudock = true;
            nftIdsToWithdraw = _getIdsOfItemsToSend(minimumReceived);
        }
        // otherwise, if fulfiller is spending ERC721 tokens, calculate the amount of ERC20 tokens to pay for
        // N items
        else {
            CurveErrorCodes.Error errorCode;
            // Calculate price quoting
            uint256 outputAmount;
            (errorCode, newSpotPrice, newDelta, outputAmount, ) = pair
                .getSellNFTQuote(maximumSpent.length);
            if (errorCode != CurveErrorCodes.Error.OK) {
                revert CurveError();
            }
            offer = new SpentItem[](1);
            offer[0] = SpentItem({
                itemType: ItemType.ERC20,
                token: address(pair.token()),
                identifier: 0,
                amount: outputAmount
            });
            consideration = _convertSpentErc721sToReceivedItems(
                pair,
                maximumSpent
            );
            tokensToWithdraw = outputAmount;
        }
    }

    function _getIdsOfItemsToSend(SpentItem[] calldata minimumReceived)
        internal
        pure
        returns (uint256[] memory idsOfItemsToSend)
    {
        for (uint256 i = 0; i < minimumReceived.length; i++) {
            SpentItem calldata item = minimumReceived[i];
            idsOfItemsToSend[i] = item.identifier;
        }
    }

    function _convertSpentErc721sToReceivedItems(
        ILSSVMPair pair,
        SpentItem[] calldata spentItems
    ) internal view returns (ReceivedItem[] memory receivedItems) {
        receivedItems = new ReceivedItem[](spentItems.length);
        for (uint256 i = 0; i < spentItems.length; i++) {
            SpentItem calldata spentItem = spentItems[i];
            receivedItems[i] = ReceivedItem({
                itemType: ItemType.ERC721,
                token: address(pair.nft()),
                identifier: spentItem.identifier,
                amount: spentItem.amount,
                recipient: payable(address(this))
            });
        }
    }

    /// @dev validate SpentItem
    function _validateSpentItem(
        ILSSVMPair pair,
        SpentItem calldata offerItem,
        ItemType homogenousType,
        bool nft,
        bool offer
    ) internal view {
        // Ensure that item type is valid.
        ItemType offerItemType = offerItem.itemType;
        if (offerItemType == ItemType.ERC721_WITH_CRITERIA) {
            // maximumSpent items must not be criteria items, since they will not be resolved
            if (!offer) {
                revert InvalidItemType();
            }
            offerItemType = ItemType.ERC721;
        }
        // don't allow mixing of ERC20 and ERC721 items
        if (offerItemType != homogenousType) {
            revert InvalidItemType();
        }
        // validate that the token address is correct
        if (nft) {
            if (offerItem.token != address(pair.nft())) {
                revert InvalidToken();
            }
        } else {
            if (offerItem.token != address(pair.token())) {
                revert InvalidToken();
            }
        }
    }

    function _validateSpentItems(
        ILSSVMPair pair,
        SpentItem[] calldata minimumReceived,
        bool offer
    ) internal view {
        ItemType homogenousType = minimumReceived[0].itemType;
        if (homogenousType == ItemType.ERC721_WITH_CRITERIA) {
            homogenousType = ItemType.ERC721;
        }
        if (
            homogenousType != ItemType.ERC721 &&
            homogenousType != ItemType.ERC20
        ) {
            revert InvalidItemType();
        }
        bool nft = homogenousType == ItemType.ERC721;
        for (uint256 i = 1; i < minimumReceived.length; ++i) {
            _validateSpentItem(
                pair,
                minimumReceived[i],
                homogenousType,
                nft,
                offer
            );
        }
    }

    function previewOrder(
        address,
        SpentItem[] calldata,
        SpentItem[] calldata,
        bytes calldata
    )
        external
        view
        override
        returns (SpentItem[] memory, ReceivedItem[] memory)
    {
        revert NotImplemented();
    }

    function getInventory()
        external
        pure
        override
        returns (SpentItem[] memory, SpentItem[] memory)
    {
        revert NotImplemented();
    }
}
