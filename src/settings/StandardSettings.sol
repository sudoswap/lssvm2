// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Clone} from "clones-with-immutable-args/Clone.sol";
import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IOwnershipTransferReceiver} from "../lib/IOwnershipTransferReceiver.sol";
import {OwnableWithTransferCallback} from "../lib/OwnableWithTransferCallback.sol";

import {ILSSVMPair} from "../ILSSVMPair.sol";
import {LSSVMPair} from "../LSSVMPair.sol";
import {ILSSVMPairFactoryLike} from "../ILSSVMPairFactoryLike.sol";
import {ISettings} from "./ISettings.sol";
import {Splitter} from "./Splitter.sol";

contract StandardSettings is IOwnershipTransferReceiver, OwnableWithTransferCallback, Clone, ISettings {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for address payable;

    uint96 constant MAX_SETTABLE_FEE = 2e17; // Max fee of 20%

    mapping(address => PairInfo) public pairInfos;
    address payable public settingsFeeRecipient;

    Splitter immutable splitterImplementation;
    ILSSVMPairFactoryLike immutable pairFactory;

    event SettingsAddedForPair(address pairAddress);
    event SettingsRemovedForPair(address pairAddress);

    constructor(Splitter _splitterImplementation, ILSSVMPairFactoryLike _pairFactory) {
        splitterImplementation = _splitterImplementation;
        pairFactory = _pairFactory;
    }

    function initialize(address _owner, address payable _settingsFeeRecipient) public {
        require(owner() == address(0), "Initialized");
        __Ownable_init(_owner);
        settingsFeeRecipient = _settingsFeeRecipient;
    }

    // Immutable params

    /**
     * @return Returns the upfront cost to enter into the Settings, in ETH
     */
    function getSettingsCost() public pure returns (uint256) {
        return _getArgUint256(0);
    }

    /**
     * @return Returns the minimum lock duration of the Settings, in seconds
     */
    function getLockDuration() public pure returns (uint64) {
        return _getArgUint64(32);
    }

    /**
     * @return Returns the trade fee split for the duration of the Settings, in bps
     */
    function getFeeSplitBps() public pure returns (uint64) {
        return _getArgUint64(40);
    }

    /**
     * @return Returns the modified royalty amount for the duration of the Settings, in bps
     */
    function getSettingsRoyaltyBps() public pure returns (uint64) {
        return _getArgUint64(48);
    }

    // Admin functions

    /**
     * @param newFeeRecipient The address to receive all payments plus trade fees
     */
    function setSettingsFeeRecipient(address payable newFeeRecipient) public onlyOwner {
        settingsFeeRecipient = newFeeRecipient;
    }

    // View functions

    /**
     * @param pairAddress The address of the pair to look up
     * @return Returns the previously set fee recipient address for a pair
     */
    function getPrevFeeRecipientForPair(address pairAddress) public view returns (address) {
        return pairInfos[pairAddress].prevFeeRecipient;
    }

    /**
     * @notice Fetches the royalty info for a pair address
     * @param pairAddress The address of the pair to look up
     * @return Returns whether the royalty is enabled and the royalty bps if enabled
     */
    function getRoyaltyInfo(address pairAddress) external view returns (bool, uint96) {
        if (LSSVMPair(pairAddress).owner() == address(this)) {
            return (true, getSettingsRoyaltyBps());
        }
        return (false, 0);
    }

    // Functions intended to be called by the pair or pair owner

    /**
     * @notice Callback after ownership is transferred to this contract from a pair
     * This function performs the following:
     * - upfront payment, if any, is taken
     * - pair verification and nft verification (done in pair factory external call)
     * - the modified royalty bps is set (done in pair factory external call)
     * - the previous fee recipient / owner parameters are recorded and saved
     * - a new fee splitter clone is deployed
     * - the fee recipient of the pair is set to the fee splitter
     * @param prevOwner The owner of the pair calling transferOwnership
     */
    function onOwnershipTransferred(address prevOwner, bytes memory) public payable {
        ILSSVMPair pair = ILSSVMPair(msg.sender);

        // Only for trade pairs
        require(pair.poolType() == ILSSVMPair.PoolType.TRADE, "Only TRADE pairs");

        // Prevent high-fee trading pairs
        require(pair.fee() <= MAX_SETTABLE_FEE, "Fee too high");

        // Verify the upfront cost
        require(msg.value == getSettingsCost(), "Insufficient payment");

        // Transfer the ETH to the fee recipient
        if (msg.value > 0) {
            settingsFeeRecipient.safeTransferETH(msg.value);
        }

        // Enable settings in factory contract. This also validates that msg.sender is a valid pair.
        try pairFactory.enableSettingsForPair(address(this), msg.sender) {}
        catch (bytes memory) {
            revert("Pair verification failed");
        }

        // Store the original owner, unlock date, and old fee recipient
        pairInfos[msg.sender] = PairInfo({
            prevOwner: prevOwner,
            unlockTime: uint96(block.timestamp) + getLockDuration(),
            prevFeeRecipient: ILSSVMPair(msg.sender).getFeeRecipient()
        });

        // Deploy the fee splitter clone
        // param1 = parent Settings address, i.e. address(this)
        // param2 = pair address, i.e. msg.sender
        bytes memory data = abi.encodePacked(address(this), msg.sender);
        address splitterAddress = address(splitterImplementation).clone(data);

        // Set the asset (i.e. fee) recipient to be the splitter clone
        ILSSVMPair(msg.sender).changeAssetRecipient(payable(splitterAddress));

        emit SettingsAddedForPair(msg.sender);
    }

    /**
     * @notice Transfers ownership of the pair back to the original owner
     * @param pairAddress The address of the pair to reclaim ownership
     */
    function reclaimPair(address pairAddress) public {
        PairInfo memory pairInfo = pairInfos[pairAddress];

        ILSSVMPair pair = ILSSVMPair(pairAddress);

        // Verify that the caller is the previous pair owner or admin of the NFT collection
        if (msg.sender == pairInfo.prevOwner) {
            // If previous owner, verify that the current time is past the unlock time
            require(block.timestamp > pairInfo.unlockTime, "Lockup not over");
        }
        // Otherwise, if not an authorized address, revert
        else if (!pairFactory.authAllowedForToken(address(pair.nft()), msg.sender)) {
            revert("Not prev owner or collection admin");
        }

        // Split fees (if applicable)
        if (
            pairFactory.isPair(pairAddress, ILSSVMPairFactoryLike.PairVariant.ERC721_ETH)
                || pairFactory.isPair(pairAddress, ILSSVMPairFactoryLike.PairVariant.ERC1155_ETH)
        ) {
            Splitter(payable(pair.getFeeRecipient())).withdrawAllETHInSplitter();
        } else if (
            pairFactory.isPair(pairAddress, ILSSVMPairFactoryLike.PairVariant.ERC721_ERC20)
                || pairFactory.isPair(pairAddress, ILSSVMPairFactoryLike.PairVariant.ERC1155_ERC20)
        ) {
            Splitter(payable(pair.getFeeRecipient())).withdrawAllBaseQuoteTokens();
        }

        // Change the fee recipient back
        pair.changeAssetRecipient(payable(pairInfo.prevFeeRecipient));

        // Disable the royalty override
        pairFactory.disableSettingsForPair(address(this), pairAddress);

        // Transfer ownership back to original pair owner
        OwnableWithTransferCallback(pairAddress).transferOwnership(pairInfo.prevOwner, "");

        // Remove pairInfo entry
        delete pairInfos[pairAddress];

        emit SettingsRemovedForPair(pairAddress);
    }

    /**
     * @notice Allows a pair owner to adjust fee % even while a pair has Settings enabled
     * @param pairAddress The address of the pair to change fee
     * @param newFee The new fee to set the pair to, subject to MAX_FEE or less
     */
    function changeFee(address pairAddress, uint96 newFee) public {
        PairInfo memory pairInfo = pairInfos[pairAddress];
        // Verify that the caller is the previous owner of the pair
        require(msg.sender == pairInfo.prevOwner, "Not prev owner");
        require(newFee <= MAX_SETTABLE_FEE, "Fee too high");
        ILSSVMPair(pairAddress).changeFee(newFee);
    }

    /**
     * @notice Allows a pair owner to adjust spot price / delta even while a pair is in an Settings, subject to liquidity considerations
     * @param pairAddress The address of the pair to change spot price and delta for
     * @param newSpotPrice The new spot price
     * @param newDelta The new delta
     */
    function changeSpotPriceAndDelta(address pairAddress, uint128 newSpotPrice, uint128 newDelta, uint256 assetId)
        public
    {
        PairInfo memory pairInfo = pairInfos[pairAddress];

        // Verify that the caller is the previous owner of the pair
        require(msg.sender == pairInfo.prevOwner, "Not prev owner");

        ILSSVMPair pair = ILSSVMPair(pairAddress);

        // Get current price to buy from pair
        (,,, uint256 priceToBuyFromPair,) = pair.getBuyNFTQuote(1);

        // Get new price to buy from pair
        (
            ,
            ,
            ,
            /* error */
            /* new spot price */
            /* new delta */
            uint256 newPriceToBuyFromPair, /* trade fee */ /* protocol fee */
            ,
        ) = pair.bondingCurve().getBuyInfo(newSpotPrice, newDelta, 1, pair.fee(), pairFactory.protocolFeeMultiplier());

        // If the price to buy is now lower (i.e. NFTs are now cheaper), and there is at least 1 NFT in pair, then make the change
        if ((newPriceToBuyFromPair < priceToBuyFromPair) && pair.nft().balanceOf(pairAddress) >= 1) {
            pair.changeSpotPrice(newSpotPrice);
            pair.changeDelta(newDelta);
            return;
        }

        // Get current price to buy from pair
        (,,, uint256 priceToSellToPair,,) = pair.getSellNFTQuote(assetId, 1);

        // Get new price to sell to pair
        (
            ,
            ,
            ,
            /* error */
            /* new spot price */
            /* new delta */
            uint256 newPriceToSellToPair, /* trade fee */ /* protocol fee */
            ,
        ) = pair.bondingCurve().getSellInfo(newSpotPrice, newDelta, 1, pair.fee(), pairFactory.protocolFeeMultiplier());

        // Get token balance of the pair (ETH or ERC20)
        uint256 pairBalance;
        if (
            pairFactory.isPair(pairAddress, ILSSVMPairFactoryLike.PairVariant.ERC721_ETH)
                || pairFactory.isPair(pairAddress, ILSSVMPairFactoryLike.PairVariant.ERC1155_ETH)
        ) {
            pairBalance = pairAddress.balance;
        } else if (
            pairFactory.isPair(pairAddress, ILSSVMPairFactoryLike.PairVariant.ERC721_ERC20)
                || pairFactory.isPair(pairAddress, ILSSVMPairFactoryLike.PairVariant.ERC1155_ERC20)
        ) {
            pairBalance = pair.token().balanceOf(pairAddress);
        }

        // If the new sell price is higher, and there is enough liquidity to support at least 1 sell, then make the change
        if ((newPriceToSellToPair > priceToSellToPair) && pairBalance > newPriceToSellToPair) {
            pair.changeSpotPrice(newSpotPrice);
            pair.changeDelta(newDelta);
            return;
        }

        revert("Pricing and liquidity mismatch");
    }

    /**
     * @notice Allows owners or pair owners to bulk withdraw trade fees from a series of Splitters
     * @param splitterAddresses List of addresses of Splitters to withdraw from
     * @param isETHPair If the underlying Splitter's pair is an ETH pair or not
     */
    function bulkWithdrawFees(address[] calldata splitterAddresses, bool[] calldata isETHPair) external {
        for (uint256 i; i < splitterAddresses.length;) {
            Splitter splitter = Splitter(payable(splitterAddresses[i]));
            if (isETHPair[i]) {
                splitter.withdrawAllETHInSplitter();
            } else {
                splitter.withdrawAllBaseQuoteTokens();
            }
            unchecked {
                ++i;
            }
        }
    }
}
