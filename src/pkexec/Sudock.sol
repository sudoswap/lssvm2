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
import {LSSVMPairETH} from "../LSSVMPairETH.sol";
import {LSSVMPairERC721} from "../erc721/LSSVMPairERC721.sol";
import {ILSSVMPair} from "../ILSSVMPair.sol";
import {ILSSVMPairFactoryLike} from "../ILSSVMPairFactoryLike.sol";
import {ICurve} from "../bonding-curves/ICurve.sol";
import {CurveErrorCodes} from "../bonding-curves/CurveErrorCodes.sol";

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

    struct EthPayment {
        address payable recipient;
        uint256 amount;
    }

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

    function _calculateBondingCurveBuy(LSSVMPair pair, ILSSVMPairFactoryLike pairFactory, uint256 nftId) internal view returns (ReceivedItem[] memory consideration, uint256 newSpotPrice, uint256 newDelta) {

        CurveErrorCodes.Error errorCode;
        uint256 inputAmount;
        uint256 tradeFee;
        uint256 protocolFee;

        // Get the amounts from the bonding curve, assuming we purchase 1 item
        (
            errorCode,
            newSpotPrice,
            newDelta,
            inputAmount,
            tradeFee,
            protocolFee
        ) = ICurve(pair.bondingCurve()).getBuyInfo(
            pair.spotPrice(),
            pair.delta(),
            1,
            pair.fee(),
            pairFactory.protocolFeeMultiplier()
        );
        require(errorCode == CurveErrorCodes.Error.OK, "Curve error");
        // Calculate the royalties
        uint256 saleAmount = inputAmount - tradeFee - protocolFee;
        (
            address payable[] memory royaltyRecipients,
            uint256[] memory royaltyAmounts,

        ) = pair.calculateRoyaltiesView(nftId, saleAmount);

        consideration = new ReceivedItem[](3 + royaltyRecipients.length);

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
            recipient: payable(address(pairFactory))
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

    function _calculateBondingCurveSell(LSSVMPair pair, ILSSVMPairFactoryLike pairFactory, uint256 nftId) internal view returns (uint256 newSpotPrice, uint256 newDelta, EthPayment[] memory amountsAndRecipients) {

        CurveErrorCodes.Error errorCode;
        uint256 outputAmount;
        uint256 tradeFee;
        uint256 protocolFee;

        // Get the amounts from the bonding curve, assuming we sell 1 item to the pool
        (
            errorCode,
            newSpotPrice,
            newDelta,
            outputAmount,
            tradeFee,
            protocolFee
        ) = ICurve(pair.bondingCurve()).getSellInfo(
            pair.spotPrice(),
            pair.delta(),
            1,
            pair.fee(),
            pairFactory.protocolFeeMultiplier()
        );
        require(errorCode == CurveErrorCodes.Error.OK, "Curve error");

        // Calculate the royalties
        uint256 saleAmount = outputAmount;
        (
            address payable[] memory royaltyRecipients,
            uint256[] memory royaltyAmounts,

        ) = pair.calculateRoyaltiesView(nftId, saleAmount);

        amountsAndRecipients = new EthPayment[](2 + royaltyAmounts.length);
        amountsAndRecipients[0].amount = outputAmount;
        amountsAndRecipients[1].amount = protocolFee;
        amountsAndRecipients[1].recipient = payable(address(pairFactory));

        // amountsAndRecipients[0] = the amount / the caller
        // amountsAndRecipients[1] = the protocol fee / the pair factory
        // amountsAndRecipients[2+] = the royalties / recipients

        for (uint i; i < royaltyAmounts.length; ++i) {
            amountsAndRecipients[2 + i].amount = royaltyAmounts[i];
            amountsAndRecipients[2 + i].recipient = royaltyRecipients[i];
        }
    }

    function _generateOrder(
        SpentItem[] calldata minimumReceived, // Goes from pool
        SpentItem[] calldata maximumSpent, // Goes to pool
        bytes calldata context
    )
        internal
        view
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration, uint256 newSpotPrice, uint256 newDelta, EthPayment[] memory amountsAndRecipients)
    {
        LSSVMPair pair = LSSVMPair(abi.decode(context, (address)));
        address nftAddress = pair.nft();
        ILSSVMPairFactoryLike pairFactory = pair.factory();

        // If we are sending an ERC721 to the caller, then the caller is buying an ERC721 with ETH
        if (minimumReceived.length > 0 && minimumReceived[0].itemType == ItemType.ERC721) {
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

            (consideration, newSpotPrice, newDelta) = _calculateBondingCurveBuy(pair, pairFactory, nftId);
        }
        // If we are taking in an ERC721, we are sending ETH to the caller
        else if (maximumSpent.length > 0 && maximumSpent[0].itemType == ItemType.ERC721) {

            // Validate the amount to receive
            require(maximumSpent[0].token == nftAddress, "Invalid NFT");
            require(maximumSpent[0].amount == 1, "Invalid amount");

            // Assume the caller has specified the ID of the ERC721 they want to purchase from the pool
            uint256 nftId = maximumSpent[0].identifier;

            // Set consideration to receive the ID the caller wants to sell
            consideration = new ReceivedItem[](1);
            consideration[0] = ReceivedItem({
                itemType: maximumSpent[0].itemType,
                token: nftAddress,
                identifier: nftId,
                amount: 1,
                recipient: payable(address(pair))
            });
            
            // Query the bonding curve
            (newSpotPrice, newDelta, amountsAndRecipients) =  _calculateBondingCurveSell(pair, pairFactory, nftId);

            // Set offer to be the ETH amount from the amountsAndRecipients[0] amount
            offer = new SpentItem[](1);
            offer[0] = SpentItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifier: 0,
                amount: amountsAndRecipients[0].amount
            }); 

            // Validate that the ETH in the pair is at least the total amount
            uint256 totalOutput;
            for (uint i; i < amountsAndRecipients.length; ++i) {
                totalOutput += amountsAndRecipients[i].amount;
            }
            require(address(pair).balance >= totalOutput, "Too little ETH");
        }
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
        uint256 newSpotPrice;
        uint256 newDelta;
        EthPayment[] memory amountsAndRecipients;
        (offer, consideration, newSpotPrice, newDelta, amountsAndRecipients) =  _generateOrder(minimumReceived, maximumSpent, context);

        // Update spot price and delta
        LSSVMPair(abi.decode(context, (address))).changeSpotPrice(uint128(newSpotPrice));
        LSSVMPair(abi.decode(context, (address))).changeDelta(uint128(newDelta));

        // Either send ETH to Seaport or pull NFTs from the pool
        // If no recipients, then we pull the NFT from the pool
        if (amountsAndRecipients.length == 0) {
            uint256[] memory nftIds = new uint256[](1);
            nftIds[0] = minimumReceived[0].identifier;
            LSSVMPair(abi.decode(context, (address))).withdrawERC721(IERC721(LSSVMPair(abi.decode(context, (address))).nft()), nftIds);
        }
        // If recipients, then we send the ETH to all of the fee recipients, as well as Seaport
        else {
            
            // Withdraw all the ETH needed
            uint256 totalToWithdraw;
            for (uint i = 0; i < amountsAndRecipients.length; ++i) {
                totalToWithdraw += amountsAndRecipients[0].amount;
            }
            LSSVMPairETH(abi.decode(context, (address))).withdrawETH(totalToWithdraw);

            // Send ETH to Seaport.
            (bool success, ) = SEAPORT.call{ value: amountsAndRecipients[0].amount }("");

            // Revert if transaction fails.
            if (!success) {
                assembly {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }

            // Send ETH to all other recipients
            for (uint i = 1; i < amountsAndRecipients.length; ++i) {
                (success, ) = amountsAndRecipients[i].recipient.call{ value: amountsAndRecipients[i].amount }("");
                // Revert if transaction fails.
                if (!success) {
                    assembly {
                        returndatacopy(0, 0, returndatasize())
                        revert(0, returndatasize())
                    }
                }
            }
        }
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
        (offer, consideration, , ,) = _generateOrder(getFromPool, giveToPool, context);
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
