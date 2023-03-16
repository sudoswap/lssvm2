// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IRoyaltyEngineV1} from "manifoldxyz/IRoyaltyEngineV1.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {LSSVMRouter} from "./LSSVMRouter.sol";
import {ICurve} from "./bonding-curves/ICurve.sol";
import {ReentrancyGuard} from "./lib/ReentrancyGuard.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {CurveErrorCodes} from "./bonding-curves/CurveErrorCodes.sol";
import {IOwnershipTransferReceiver} from "./lib/IOwnershipTransferReceiver.sol";
import {OwnableWithTransferCallback} from "./lib/OwnableWithTransferCallback.sol";

/// @title The base contract for an NFT/TOKEN AMM pair
/// @author boredGenius and 0xmons
/// @notice This implements the core swap logic from NFT to TOKEN
abstract contract LSSVMPair is OwnableWithTransferCallback, ERC721Holder, ERC1155Holder {
    /**
     * Library usage
     */

    using Address for address;
    using FixedPointMathLib for uint256;

    /**
     *  Enums
     */

    enum PoolType {
        TOKEN,
        NFT,
        TRADE
    }

    /**
     * Constants
     */

    /// @dev 50%, must <= 1 - MAX_PROTOCOL_FEE (set in LSSVMPairFactory)
    uint256 internal constant MAX_TRADE_FEE = 0.5e18;

    /**
     *  Immutable params
     */

    // Sudoswap Royalty Engine
    IRoyaltyEngineV1 public immutable ROYALTY_ENGINE;

    /**
     *  Storage variables
     */

    // @dev This is generally used to mean the immediate sell price for the next marginal NFT.
    // However, this should NOT be assumed, as bonding curves may use spotPrice in different ways.
    // Use getBuyNFTQuote and getSellNFTQuote for accurate pricing info.
    uint128 public spotPrice;

    // The parameter for the pair's bonding curve.
    // Units and meaning are bonding curve dependent.
    uint128 public delta;

    // The spread between buy and sell prices, set to be a multiplier we apply to the buy price
    // Fee is only relevant for TRADE pools
    // Units are in base 1e18
    uint96 public fee;

    // The address that swapped assets are sent to
    // For TRADE pools, assets are always sent to the pool, so this is used to track trade fee
    // If set to address(0), will default to owner() for NFT and TOKEN pools
    address payable internal assetRecipient;

    /**
     *  Events
     */

    event SwapNFTInPair(uint256 amountIn, uint256[] ids);
    event SwapNFTInPair(uint256 amountIn, uint256 numNFTs);
    event SwapNFTOutPair(uint256 amountOut, uint256[] ids);
    event SwapNFTOutPair(uint256 amountOut, uint256 numNFTs);
    event SpotPriceUpdate(uint128 newSpotPrice);
    event TokenDeposit(uint256 amount);
    event TokenWithdrawal(uint256 amount);
    event NFTWithdrawal(uint256[] ids);
    event NFTWithdrawal(uint256 numNFTs);
    event DeltaUpdate(uint128 newDelta);
    event FeeUpdate(uint96 newFee);
    event AssetRecipientChange(address indexed a);

    /**
     *  Errors
     */

    error BondingCurveError(CurveErrorCodes.Error error);

    constructor(IRoyaltyEngineV1 royaltyEngine) {
        ROYALTY_ENGINE = royaltyEngine;
    }

    /**
     * @notice Called during pair creation to set initial parameters
     *   @dev Only called once by factory to initialize.
     *   We verify this by making sure that the current owner is address(0).
     *   The Ownable library we use disallows setting the owner to be address(0), so this condition
     *   should only be valid before the first initialize call.
     *   @param _owner The owner of the pair
     *   @param _assetRecipient The address that will receive the TOKEN or NFT sent to this pair during swaps. NOTE: If set to address(0), they will go to the pair itself.
     *   @param _delta The initial delta of the bonding curve
     *   @param _fee The initial % fee taken, if this is a trade pair
     *   @param _spotPrice The initial price to sell an asset into the pair
     */
    function initialize(
        address _owner,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice
    ) external {
        require(owner() == address(0), "Initialized");
        __Ownable_init(_owner);

        ICurve _bondingCurve = bondingCurve();
        PoolType _poolType = poolType();

        if ((_poolType == PoolType.TOKEN) || (_poolType == PoolType.NFT)) {
            require(_fee == 0, "Only Trade Pools can have nonzero fee");
        } else if (_poolType == PoolType.TRADE) {
            require(_fee < MAX_TRADE_FEE, "Trade fee must be less than 90%");
            fee = _fee;
        }

        // Set asset recipient if it's not address(0)
        if (_assetRecipient != address(0)) {
            assetRecipient = _assetRecipient;
        }

        require(_bondingCurve.validateDelta(_delta), "Invalid delta for curve");
        require(_bondingCurve.validateSpotPrice(_spotPrice), "Invalid new spot price for curve");
        delta = _delta;
        spotPrice = _spotPrice;
    }

    /**
     * External state-changing functions
     */

    /**
     * @notice Sends token to the pair in exchange for a specific set of NFTs
     *     @dev To compute the amount of token to send, call bondingCurve.getBuyInfo
     *     This swap is meant for users who want specific IDs. Also higher chance of
     *     reverting if some of the specified IDs leave the pool before the swap goes through.
     *     @param nftIds The list of IDs of the NFTs to purchase
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
        uint256[] calldata nftIds,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool isRouter,
        address routerCaller
    ) external payable virtual returns (uint256 inputAmount);

    /**
     * @notice Sends a set of NFTs to the pair in exchange for token
     *     @dev To compute the amount of token to that will be received, call bondingCurve.getSellInfo.
     *     @param nftIds The list of IDs of the NFTs to sell to the pair
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
        uint256[] calldata nftIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bool isRouter,
        address routerCaller
    ) external virtual returns (uint256 outputAmount);

    /**
     * View functions
     */

    /**
     * @dev Used as read function to query the bonding curve for buy pricing info
     *     @param numNFTs The number of NFTs to buy from the pair
     */
    function getBuyNFTQuote(uint256 numNFTs)
        external
        view
        returns (
            CurveErrorCodes.Error error,
            uint256 newSpotPrice,
            uint256 newDelta,
            uint256 inputAmount,
            uint256 protocolFee
        )
    {
        (error, newSpotPrice, newDelta, inputAmount, /* tradeFee */, protocolFee) =
            bondingCurve().getBuyInfo(spotPrice, delta, numNFTs, fee, factory().protocolFeeMultiplier());
    }

    /**
     * @dev Used as read function to query the bonding curve for sell pricing info including royalties
     *     @param numNFTs The number of NFTs to sell to the pair
     */
    function getSellNFTQuote(uint256 assetId, uint256 numNFTs)
        external
        view
        returns (
            CurveErrorCodes.Error error,
            uint256 newSpotPrice,
            uint256 newDelta,
            uint256 outputAmount,
            uint256 protocolFee,
            uint256 royaltyAmount
        )
    {
        (error, newSpotPrice, newDelta, outputAmount, /* tradeFee */, protocolFee) =
            bondingCurve().getSellInfo(spotPrice, delta, numNFTs, fee, factory().protocolFeeMultiplier());

        if (numNFTs != 0) {
            // Compute royalties
            (,, royaltyAmount) = calculateRoyaltiesView(assetId, outputAmount);

            // Deduct royalties from outputAmount
            unchecked {
                // Safe because we already require outputAmount >= royaltyAmount in _calculateRoyalties()
                outputAmount -= royaltyAmount;
            }
        }
    }

    /**
     * @notice Returns the pair's variant (Pair uses ETH or ERC20)
     */
    function pairVariant() public pure virtual returns (ILSSVMPairFactoryLike.PairVariant);

    function factory() public pure returns (ILSSVMPairFactoryLike _factory) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _factory := shr(0x60, calldataload(sub(calldatasize(), paramsLength)))
        }
    }

    /**
     * @notice Returns the type of bonding curve that parameterizes the pair
     */
    function bondingCurve() public pure returns (ICurve _bondingCurve) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _bondingCurve := shr(0x60, calldataload(add(sub(calldatasize(), paramsLength), 20)))
        }
    }

    /**
     * @notice Returns the address of NFT collection that parameterizes the pair
     */
    function nft() public pure returns (address _nft) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _nft := shr(0x60, calldataload(add(sub(calldatasize(), paramsLength), 40)))
        }
    }

    /**
     * @notice Returns the pair's type (TOKEN/NFT/TRADE)
     */
    function poolType() public pure returns (PoolType _poolType) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _poolType := shr(0xf8, calldataload(add(sub(calldatasize(), paramsLength), 60)))
        }
    }

    /**
     * @notice Returns the address that assets that receives assets when a swap is done with this pair
     *     Can be set to another address by the owner, but has no effect on TRADE pools
     *     If set to address(0), defaults to owner() for NFT/TOKEN pools
     */
    function getAssetRecipient() public view returns (address payable) {
        // TRADE pools will always receive the asset themselves
        if (poolType() == PoolType.TRADE) {
            return payable(address(this));
        }

        address payable _assetRecipient = assetRecipient;

        // Otherwise, we return the recipient if it's been set
        // Or, we replace it with owner() if it's address(0)
        if (_assetRecipient == address(0)) {
            return payable(owner());
        }
        return _assetRecipient;
    }

    /**
     * @notice Returns the address that receives trade fees when a swap is done with this pair
     *      Only relevant for TRADE pools
     *      If set to address(0), defaults to the pair itself
     */
    function getFeeRecipient() public view returns (address payable _feeRecipient) {
        _feeRecipient = assetRecipient;
        if (_feeRecipient == address(0)) {
            _feeRecipient = payable(address(this));
        }
    }

    /**
     * Internal functions
     */

    /**
     * @notice Calculates the amount needed to be sent into the pair for a buy and adjusts spot price or delta if necessary
     *     @param numNFTs The amount of NFTs to purchase from the pair
     *     @param _bondingCurve The bonding curve to use for price calculation
     *     @param _factory The factory to use for protocol fee lookup
     *     @return tradeFee The amount of tokens to send as trade fee
     *     @return protocolFee The amount of tokens to send as protocol fee
     *     @return inputAmount The amount of tokens total tokens receive
     */
    function _calculateBuyInfoAndUpdatePoolParams(uint256 numNFTs, ICurve _bondingCurve, ILSSVMPairFactoryLike _factory)
        internal
        returns (uint256 tradeFee, uint256 protocolFee, uint256 inputAmount)
    {
        CurveErrorCodes.Error error;
        // Save on 2 SLOADs by caching
        uint128 currentSpotPrice = spotPrice;
        uint128 currentDelta = delta;
        uint128 newDelta;
        uint128 newSpotPrice;
        (error, newSpotPrice, newDelta, inputAmount, tradeFee, protocolFee) =
            _bondingCurve.getBuyInfo(currentSpotPrice, currentDelta, numNFTs, fee, _factory.protocolFeeMultiplier());

        // Revert if bonding curve had an error
        if (error != CurveErrorCodes.Error.OK) {
            revert BondingCurveError(error);
        }

        // Consolidate writes to save gas
        if (currentSpotPrice != newSpotPrice || currentDelta != newDelta) {
            spotPrice = newSpotPrice;
            delta = newDelta;
        }

        // Emit spot price update if it has been updated
        if (currentSpotPrice != newSpotPrice) {
            emit SpotPriceUpdate(newSpotPrice);
        }

        // Emit delta update if it has been updated
        if (currentDelta != newDelta) {
            emit DeltaUpdate(newDelta);
        }
    }

    /**
     * @notice Calculates the amount needed to be sent by the pair for a sell and adjusts spot price or delta if necessary
     *     @param numNFTs The amount of NFTs to send to the the pair
     *     @param _bondingCurve The bonding curve to use for price calculation
     *     @param _factory The factory to use for protocol fee lookup
     *     @return protocolFee The amount of tokens to send as protocol fee
     *     @return outputAmount The amount of tokens total tokens receive
     */
    function _calculateSellInfoAndUpdatePoolParams(
        uint256 numNFTs,
        ICurve _bondingCurve,
        ILSSVMPairFactoryLike _factory
    ) internal returns (uint256 protocolFee, uint256 outputAmount) {
        CurveErrorCodes.Error error;
        // Save on 2 SLOADs by caching
        uint128 currentSpotPrice = spotPrice;
        uint128 currentDelta = delta;
        uint128 newSpotPrice;
        uint128 newDelta;
        (error, newSpotPrice, newDelta, outputAmount, /*tradeFee*/, protocolFee) =
            _bondingCurve.getSellInfo(currentSpotPrice, currentDelta, numNFTs, fee, _factory.protocolFeeMultiplier());

        // Revert if bonding curve had an error
        if (error != CurveErrorCodes.Error.OK) {
            revert BondingCurveError(error);
        }

        // Consolidate writes to save gas
        if (currentSpotPrice != newSpotPrice || currentDelta != newDelta) {
            spotPrice = newSpotPrice;
            delta = newDelta;
        }

        // Emit spot price update if it has been updated
        if (currentSpotPrice != newSpotPrice) {
            emit SpotPriceUpdate(newSpotPrice);
        }

        // Emit delta update if it has been updated
        if (currentDelta != newDelta) {
            emit DeltaUpdate(newDelta);
        }
    }

    /**
     * @notice Pulls the token input of a trade from the trader and pays the protocol fee.
     *     @param assetId The first ID of the asset to be swapped for
     *     @param inputAmount The amount of tokens to be sent
     *     @param tradeFeeAmount The amount of tokens to be sent as trade fee (if applicable)
     *     @param isRouter Whether or not the caller is LSSVMRouter
     *     @param routerCaller If called from LSSVMRouter, store the original caller
     *     @param _factory The LSSVMPairFactory which stores LSSVMRouter allowlist info
     *     @param protocolFee The protocol fee to be paid
     */
    function _pullTokenInputAndPayProtocolFee(
        uint256 assetId,
        uint256 inputAmount,
        uint256 tradeFeeAmount,
        bool isRouter,
        address routerCaller,
        ILSSVMPairFactoryLike _factory,
        uint256 protocolFee
    ) internal virtual;

    /**
     * @notice Sends excess tokens back to the caller (if applicable)
     * @dev Swap callers interacting with an ETH pair must be able to receive ETH (e.g. if the caller sends too much ETH)
     */
    function _refundTokenToSender(uint256 inputAmount) internal virtual;

    /**
     * @notice Sends tokens to a recipient
     *     @param tokenRecipient The address receiving the tokens
     *     @param outputAmount The amount of tokens to send
     */
    function _sendTokenOutput(address payable tokenRecipient, uint256 outputAmount) internal virtual;

    /**
     * @dev Used internally to grab pair parameters from calldata, see LSSVMPairCloner for technical details
     */
    function _immutableParamsLength() internal pure virtual returns (uint256);

    /**
     * Royalty support functions
     */

    function _calculateRoyalties(uint256 assetId, uint256 saleAmount)
        internal
        returns (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 royaltyTotal)
    {
        (address payable[] memory recipients, uint256[] memory amounts) =
            ROYALTY_ENGINE.getRoyalty(nft(), assetId, saleAmount);
        return _calculateRoyaltiesLogic(recipients, amounts, saleAmount);
    }

    /**
     * @dev Same as _calculateRoyalties, but uses getRoyaltyView to avoid state mutations and is public for external callers
     */
    function calculateRoyaltiesView(uint256 assetId, uint256 saleAmount)
        public
        view
        returns (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 royaltyTotal)
    {
        (address payable[] memory recipients, uint256[] memory amounts) =
            ROYALTY_ENGINE.getRoyaltyView(nft(), assetId, saleAmount);
        return _calculateRoyaltiesLogic(recipients, amounts, saleAmount);
    }

    /**
     * @dev Common logic used by _calculateRoyalties() and calculateRoyaltiesView()
     */
    function _calculateRoyaltiesLogic(address payable[] memory recipients, uint256[] memory amounts, uint256 saleAmount)
        internal
        view
        returns (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 royaltyTotal)
    {
        if (recipients.length != 0) {
            // If a pair has custom Settings, use the overridden royalty amount and only use the first receiver
            (bool settingsEnabled, uint96 bps) = factory().getSettingsForPair(address(this));
            if (settingsEnabled) {
                royaltyRecipients = new address payable[](1);
                royaltyRecipients[0] = recipients[0];
                royaltyAmounts = new uint256[](1);
                royaltyAmounts[0] = (saleAmount * bps) / 10000;
            } else {
                royaltyRecipients = recipients;
                royaltyAmounts = amounts;
            }
        }

        for (uint256 i; i < royaltyRecipients.length;) {
            royaltyTotal += royaltyAmounts[i];
            unchecked {
                ++i;
            }
        }

        // Validate royalty total is at most 25% of the sale amount
        // This defends against a rogue Manifold registry that charges extremely
        // high royalties
        require(royaltyTotal <= saleAmount >> 2, "Royalty exceeds max");
    }

    /**
     * Owner functions
     */

    /**
     * @notice Rescues a specified set of NFTs owned by the pair to the owner address. (onlyOwnable modifier is in the implemented function)
     *     @param a The NFT to transfer
     *     @param nftIds The list of IDs of the NFTs to send to the owner
     */
    function withdrawERC721(IERC721 a, uint256[] calldata nftIds) external virtual;

    /**
     * @notice Rescues ERC20 tokens from the pair to the owner. Only callable by the owner (onlyOwnable modifier is in the implemented function).
     *     @param a The token to transfer
     *     @param amount The amount of tokens to send to the owner
     */
    function withdrawERC20(ERC20 a, uint256 amount) external virtual;

    /**
     * @notice Rescues ERC1155 tokens from the pair to the owner. Only callable by the owner.
     *     @param a The NFT to transfer
     *     @param ids The NFT ids to transfer
     *     @param amounts The amounts of each id to transfer
     */
    function withdrawERC1155(IERC1155 a, uint256[] calldata ids, uint256[] calldata amounts) external virtual;

    /**
     * @notice Updates the selling spot price. Only callable by the owner.
     *     @param newSpotPrice The new selling spot price value, in Token
     */
    function changeSpotPrice(uint128 newSpotPrice) external onlyOwner {
        ICurve _bondingCurve = bondingCurve();
        require(_bondingCurve.validateSpotPrice(newSpotPrice), "Invalid new spot price for curve");
        if (spotPrice != newSpotPrice) {
            spotPrice = newSpotPrice;
            emit SpotPriceUpdate(newSpotPrice);
        }
    }

    /**
     * @notice Updates the delta parameter. Only callable by the owner.
     *     @param newDelta The new delta parameter
     */
    function changeDelta(uint128 newDelta) external onlyOwner {
        ICurve _bondingCurve = bondingCurve();
        require(_bondingCurve.validateDelta(newDelta), "Invalid delta for curve");
        if (delta != newDelta) {
            delta = newDelta;
            emit DeltaUpdate(newDelta);
        }
    }

    /**
     * @notice Updates the fee taken by the LP. Only callable by the owner.
     *     Only callable if the pool is a Trade pool. Reverts if the fee is >=
     *     MAX_FEE.
     *     @param newFee The new LP fee percentage, 18 decimals
     */
    function changeFee(uint96 newFee) external onlyOwner {
        PoolType _poolType = poolType();
        require(_poolType == PoolType.TRADE, "Only for Trade pools");
        require(newFee < MAX_TRADE_FEE, "Trade fee must be less than 50%");
        if (fee != newFee) {
            fee = newFee;
            emit FeeUpdate(newFee);
        }
    }

    /**
     * @notice Changes the address that will receive assets received from
     *     trades. Only callable by the owner.
     *     @param newRecipient The new asset recipient
     */
    function changeAssetRecipient(address payable newRecipient) external onlyOwner {
        if (assetRecipient != newRecipient) {
            assetRecipient = newRecipient;
            emit AssetRecipientChange(newRecipient);
        }
    }

    function _preCallCheck(address target) internal virtual;

    /**
     * @notice Allows the pair to make arbitrary external calls to contracts
     *     whitelisted by the protocol. Only callable by the owner.
     *     @param target The contract to call
     *     @param data The calldata to pass to the contract
     */
    function call(address payable target, bytes calldata data) external onlyOwner {
        ILSSVMPairFactoryLike _factory = factory();
        require(_factory.callAllowed(target), "Target must be whitelisted");

        // Ensure the call isn't calling a banned function
        bytes4 sig = bytes4(data[:4]);
        if (
            sig == IOwnershipTransferReceiver.onOwnershipTransferred.selector
                || sig == LSSVMRouter.pairTransferERC20From.selector || sig == LSSVMRouter.pairTransferNFTFrom.selector
                || sig == LSSVMRouter.pairTransferERC1155From.selector
        ) {
            revert("Banned function");
        }

        // Prevent calling the pair's underlying nft
        // (We ban calling the underlying NFT/ERC20 to avoid maliciously transferring assets approved for the pair to spend)
        require(target != nft(), "Banned target");

        _preCallCheck(target);

        (bool result,) = target.call{value: 0}(data);
        require(result, "Call failed");
    }

    /**
     * @notice Allows owner to batch multiple calls, forked from: https://github.com/boringcrypto/BoringSolidity/blob/master/contracts/BoringBatchable.sol
     *     @notice The revert handling is forked from: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/c239e1af8d1a1296577108dd6989a17b57434f8e/contracts/utils/Address.sol#L201
     *     @dev Intended for withdrawing/altering pool pricing in one tx, only callable by owner, cannot change owner
     *     @param calls The calldata for each call to make
     *     @param revertOnFail Whether or not to revert the entire tx if any of the calls fail. Calls to transferOwnership will revert regardless.
     */
    function multicall(bytes[] calldata calls, bool revertOnFail) external onlyOwner {
        for (uint256 i; i < calls.length;) {
            bytes4 sig = bytes4(calls[i][:4]);
            // We ban calling transferOwnership when ownership
            require(sig != transferOwnership.selector, "Banned function");

            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            if (!success && revertOnFail) {
                assembly {
                    revert(add(0x20, result), mload(result))
                }
            }

            unchecked {
                ++i;
            }
        }
    }
}
