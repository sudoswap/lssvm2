// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ReceivedItem, Schema, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {OwnableWithTransferCallback} from "../lib/OwnableWithTransferCallback.sol";
import {IOwnershipTransferReceiver} from "../lib/IOwnershipTransferReceiver.sol";
import {LSSVMPair} from "../LSSVMPair.sol";
import {LSSVMPairERC721} from "../erc721/LSSVMPairERC721.sol";
import {ILSSVMPair} from "../ILSSVMPair.sol";
import {ILSSVMPairFactoryLike} from "../ILSSVMPairFactoryLike.sol";
import {ICurve} from "../bonding-curves/ICurve.sol";

/**
 - Minimal proof-of-concept compatibility layer between sudoAMM v2 pools and Seaport
 - Only designed for 1 NFT to be swapped at a time
 */
contract Sudock is
    IOwnershipTransferReceiver,
    ContractOffererInterface,
    ERC721Holder,
    ERC165
{
    address immutable SEAPORT;
    ILSSVMPairFactoryLike immutable FACTORY;

    mapping(address => address) public prevOwnerForPair;

    error OnlySans();

    constructor(ILSSVMPairFactoryLike _FACTORY, address _SEAPORT) {
        FACTORY = _FACTORY;
        SEAPORT = _SEAPORT;
    }

    function onOwnershipTransferred(
        address _prevOwner,
        bytes memory
    ) external payable {
        // Only for pairs that are:
        // - valid pairs
        // - ERC721-ETH pairs
        // - TRADE pools
        // - no property checker set
        require(FACTORY.isValidPair(msg.sender), "Invalid pair");
        require(
            LSSVMPair(msg.sender).pairVariant() ==
                ILSSVMPairFactoryLike.PairVariant.ERC721_ETH,
            "ERC721-ETH"
        );
        require(
            ILSSVMPair(msg.sender).poolType() == ILSSVMPair.PoolType.TRADE,
            "TRADE"
        );
        require(
            LSSVMPairERC721(msg.sender).propertyChecker() == address(0),
            "0x PC"
        );

        // Check if the underlying NFT is already approved for Seaport
        // If not, set approval
        IERC721 nft = IERC721(LSSVMPair(msg.sender).nft());
        if (!nft.isApprovedForAll(address(this), SEAPORT)) {
            nft.setApprovalForAll(SEAPORT, true);
        }

        // Cache the previous owner
        prevOwnerForPair[msg.sender] = _prevOwner;
    }

    function reclaimPairs(address[] memory pairs) external {
        for (uint256 i; i < pairs.length; ) {
            require(prevOwnerForPair[pairs[i]] == msg.sender, "Not prev owner");
            LSSVMPair(pairs[i]).transferOwnership(msg.sender, "");
            delete prevOwnerForPair[pairs[i]];
            unchecked {
                ++i;
            }
        }
    }

    function _generateOrder(
        SpentItem[] calldata minimumReceived, // Goes from pool
        SpentItem[] calldata maximumSpent, // Goes to pool
        bytes calldata context
    )
        internal
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        LSSVMPair pair = LSSVMPair(abi.decode(context, (address)));
        address nftAddress = pair.nft();
        ILSSVMPairFactoryLike pairFactory = pair.factory();

        // If we are sending an ERC721 to the caller, then the caller is buying an ERC721 with ETH
        if (minimumReceived[0].itemType == ItemType.ERC721) {
            // Validate the amount to send out
            require(minimumReceived[0].token == nftAddress, "Invalid NFT");
            require(minimumReceived[0].amount == 1, "Invalid amount");

            // Assume the caller has specified the ID of the ERC721 they want to purchase from the pool
            uint256 nftId = minimumReceived[0].identifier;
            require(
                IERC721(nftAddress).ownerOf(nftId) == address(pair),
                "Unowned NFT"
            );
            require(minimumReceived.length == 1, "Too many items");

            // Grab the ID out of the pool
            {
                uint256[] memory nftIds = new uint256[](1);
                nftIds[0] = nftId;
                pair.withdrawERC721(IERC721(nftAddress), nftIds);
            }

            // Set the amount to give to be the specified NFT
            offer = minimumReceived;

            // Get the amounts from the bonding curve, assuming we purchase 1 item
            (
                ,
                uint256 newSpotPrice,
                uint256 newDelta,
                uint256 inputAmount,
                uint256 tradeFee,
                uint256 protocolFee
            ) = ICurve(pair.bondingCurve()).getBuyInfo(
                    pair.spotPrice(),
                    pair.delta(),
                    1,
                    pair.fee(),
                    pairFactory.protocolFeeMultiplier()
                );

            // Update the parameters
            pair.changeDelta(uint128(newDelta));
            pair.changeSpotPrice(uint128(newSpotPrice));

            // Calculate the royalties
            uint256 saleAmount = inputAmount - tradeFee - protocolFee;
            (
                address payable[] memory royaltyRecipients,
                uint256[] memory royaltyAmounts,

            ) = pair.calculateRoyaltiesView(nftId, saleAmount);

            // Minimum received must send the amounts to the pair, trade fee, protocol fee, and all associated royalty fees
            // Required schema:
            // maximumSpent[0] = pool amount
            // maximumSpent[1] = fee amount
            // maximumSpent[2] = protocol fee amount
            // maximumSpent[3+] = royalty amounts

            consideration = new ReceivedItem[](3 + royaltyRecipients.length);
            consideration[0] = ReceivedItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifier: 0,
                amount: saleAmount,
                recipient: payable(address(pair))
            });
            consideration[1] = ReceivedItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifier: 0,
                amount: tradeFee,
                recipient: pair.getFeeRecipient()
            });
            consideration[2] = ReceivedItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifier: 0,
                amount: protocolFee,
                recipient: pairFactory.protocolFeeRecipient()
            });

            // Set royalty recipients
            for (uint i; i < royaltyRecipients.length; ++i) {
                consideration[3 + i] = ReceivedItem({
                    itemType: ItemType.NATIVE,
                    token: address(0),
                    identifier: 0,
                    amount: royaltyAmounts[i],
                    recipient: royaltyRecipients[i]
                });
            }
        }
        // If we are sending ETH, then we will need to give out some ERC721
        else if (minimumReceived[0].itemType == ItemType.NATIVE) {}
    }

    // Does not mutate state
    function _generateOrderView(
        SpentItem[] calldata minimumReceived, // Goes from pool
        SpentItem[] calldata maximumSpent, // Goes to pool
        bytes calldata context
    )
        internal
        view
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        LSSVMPair pair = LSSVMPair(abi.decode(context, (address)));
        address nftAddress = pair.nft();
        ILSSVMPairFactoryLike pairFactory = pair.factory();

        // If we are sending an ERC721 to the caller, then the caller is buying an ERC721 with ETH
        if (minimumReceived[0].itemType == ItemType.ERC721) {
            // Validate the amount to send out
            require(minimumReceived[0].token == nftAddress, "Invalid NFT");
            require(minimumReceived[0].amount == 1, "Invalid amount");

            // Assume the caller has specified the ID of the ERC721 they want to purchase from the pool
            uint256 nftId = minimumReceived[0].identifier;
            require(
                IERC721(nftAddress).ownerOf(nftId) == address(pair),
                "Unowned NFT"
            );
            require(minimumReceived.length == 1, "Too many items");

            // Set the amount to give to be the specified NFT
            offer = minimumReceived;

            // Get the amounts from the bonding curve, assuming we purchase 1 item
            (
                ,
                uint256 newSpotPrice,
                uint256 newDelta,
                uint256 inputAmount,
                uint256 tradeFee,
                uint256 protocolFee
            ) = ICurve(pair.bondingCurve()).getBuyInfo(
                    pair.spotPrice(),
                    pair.delta(),
                    1,
                    pair.fee(),
                    pairFactory.protocolFeeMultiplier()
                );

            // Calculate the royalties
            uint256 saleAmount = inputAmount - tradeFee - protocolFee;
            (
                address payable[] memory royaltyRecipients,
                uint256[] memory royaltyAmounts,

            ) = pair.calculateRoyaltiesView(nftId, saleAmount);

            // Minimum received must send the amounts to the pair, trade fee, protocol fee, and all associated royalty fees
            // Required schema:
            // maximumSpent[0] = pool amount
            // maximumSpent[1] = fee amount
            // maximumSpent[2] = protocol fee amount
            // maximumSpent[3+] = royalty amounts

            consideration = new ReceivedItem[](3 + royaltyRecipients.length);
            consideration[0] = ReceivedItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifier: 0,
                amount: saleAmount,
                recipient: payable(address(pair))
            });
            consideration[1] = ReceivedItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifier: 0,
                amount: tradeFee,
                recipient: pair.getFeeRecipient()
            });
            consideration[2] = ReceivedItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifier: 0,
                amount: protocolFee,
                recipient: pairFactory.protocolFeeRecipient()
            });

            // Set royalty recipients
            for (uint i; i < royaltyRecipients.length; ++i) {
                consideration[3 + i] = ReceivedItem({
                    itemType: ItemType.NATIVE,
                    token: address(0),
                    identifier: 0,
                    amount: royaltyAmounts[i],
                    recipient: royaltyRecipients[i]
                });
            }
        }
        // If we are sending ETH, then we will need to give out some ERC721
        else if (minimumReceived[0].itemType == ItemType.NATIVE) {}
    }

    function generateOrder(
        address,
        SpentItem[] calldata minimumReceived, // Goes from pool
        SpentItem[] calldata maximumSpent, // Goes to pool
        bytes calldata context
    )
        external
        virtual
        override
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        if (msg.sender != SEAPORT) {
            revert OnlySans();
        }
        return _generateOrder(minimumReceived, maximumSpent, context);
    }

    function previewOrder(
        address caller,
        address,
        SpentItem[] calldata getFromPool,
        SpentItem[] calldata giveToPool,
        bytes calldata context
    )
        external
        view
        override
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        // Ensure the caller is Seaport
        if (caller != SEAPORT) {
            revert OnlySans();
        }
        return _generateOrderView(getFromPool, giveToPool, context);
    }

    // Post-execution check, we skip this
    function ratifyOrder(
        SpentItem[] calldata /* offer */,
        ReceivedItem[] calldata /* consideration */,
        bytes calldata /* context */,
        bytes32[] calldata /* orderHashes */,
        uint256 /* contractNonce */
    )
        external
        pure
        virtual
        override
        returns (bytes4 /* ratifyOrderMagicValue */)
    {
        return ContractOffererInterface.ratifyOrder.selector;
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165, ContractOffererInterface)
        returns (bool)
    {
        return
            interfaceId == type(ContractOffererInterface).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function getSeaportMetadata()
        external
        pure
        override
        returns (
            string memory name,
            Schema[] memory schemas // map to Seaport Improvement Proposal IDs
        )
    {
        schemas = new Schema[](1);
        schemas[0].id = 420;
        schemas[0].metadata = new bytes(0);

        return ("SudockContractOffererNativeToken", schemas);
    }

    receive() external payable {}
}
