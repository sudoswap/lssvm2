// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

import {Owned} from "solmate/auth/Owned.sol";

import {LSSVMPair} from "../LSSVMPair.sol";
import {IPairHooks} from "./IPairHooks.sol";
import {BasicHeap} from "../lib/BasicHeap.sol";
import {ICurve} from "../bonding-curves/ICurve.sol";
import {LSSVMPairERC20} from "../LSSVMPairERC20.sol";
import {LSSVMPairFactory} from "../LSSVMPairFactory.sol";
import {LSSVMPairERC721} from "../erc721/LSSVMPairERC721.sol";
import {LSSVMPairERC1155} from "../erc1155/LSSVMPairERC1155.sol";
import {ILSSVMPairFactoryLike} from "../ILSSVMPairFactoryLike.sol";
import {CurveErrorCodes} from "../bonding-curves/CurveErrorCodes.sol";

contract OrderBhook is IPairHooks, Owned {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeCastLib for uint256;
    using BasicHeap for BasicHeap.Heap;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error OrderBhook__InvalidPair();
    error OrderBhook__IncorrectHookAddress();
    error OrderBhook__BondingCurveNotAllowed();
    error OrderBhook__PropertyCheckerMustBeZero();

    /// -----------------------------------------------------------------------
    /// Immutable args
    /// -----------------------------------------------------------------------

    LSSVMPairFactory immutable factory;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    mapping(address => bool) public allowedCurves;

    /// @dev min heap of buy quotes
    mapping(address collection => mapping(address tokenAddress => BasicHeap.Heap)) internal _buyHeap;
    /// @dev min heap of buy quotes
    mapping(address collection => mapping(uint256 nftId => mapping(address tokenAddress => BasicHeap.Heap))) internal
        _buyHeapERC1155;

    /// @dev values are negated to implement a max heap
    mapping(address collection => mapping(address tokenAddress => BasicHeap.Heap)) internal _sellHeap;
    /// @dev values are negated to implement a max heap
    mapping(address collection => mapping(uint256 nftId => mapping(address tokenAddress => BasicHeap.Heap))) internal
        _sellHeapERC1155;

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier onlyValidPair(address pairAddress) {
        if (!factory.isValidPair(pairAddress)) revert OrderBhook__InvalidPair();
        if (
            factory.getPairNFTType(pairAddress) == ILSSVMPairFactoryLike.PairNFTType.ERC721
                && LSSVMPairERC721(pairAddress).propertyChecker() != address(0)
        ) {
            revert OrderBhook__PropertyCheckerMustBeZero();
        }
        if (!allowedCurves[address(LSSVMPair(pairAddress).bondingCurve())]) revert OrderBhook__BondingCurveNotAllowed();
        _;
    }

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(LSSVMPairFactory factory_, address owner_) Owned(owner_) {
        factory = factory_;
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    // NFT Deposit and Token Deposit are called from the Factory, not the Pair
    // So instead we have this catch-all for letting external callers (like the Factory) update state for a given pair
    function syncForPair(address pairAddress, uint256, uint256[] calldata) external onlyValidPair(pairAddress) {
        // Require that the hook is this contract
        if (address(LSSVMPair(pairAddress).hook()) != address(this)) {
            revert OrderBhook__IncorrectHookAddress();
        }
        _updateQuotesOfPair(pairAddress);
    }

    /// -----------------------------------------------------------------------
    /// View functions
    /// -----------------------------------------------------------------------

    function getBuyQuoteForPair(address pairAddress) external view returns (uint256) {
        ILSSVMPairFactoryLike.PairTokenType tokenType = factory.getPairTokenType(pairAddress);
        address tokenAddress;
        if (tokenType == ILSSVMPairFactoryLike.PairTokenType.ETH) {
            tokenAddress = address(0);
        } else {
            tokenAddress = address(LSSVMPairERC20(pairAddress).token());
        }
        ILSSVMPairFactoryLike.PairNFTType nftType = factory.getPairNFTType(pairAddress);
        BasicHeap.Heap storage heap = (nftType == ILSSVMPairFactoryLike.PairNFTType.ERC721)
            ? _buyHeap[LSSVMPair(pairAddress).nft()][tokenAddress]
            : _buyHeapERC1155[LSSVMPair(pairAddress).nft()][LSSVMPairERC1155(pairAddress).nftId()][tokenAddress];
        return uint256(-(heap.getValueOf({id: pairAddress})));
    }

    function getSellQuoteForPair(address pairAddress) external view returns (uint256) {
        ILSSVMPairFactoryLike.PairTokenType tokenType = factory.getPairTokenType(pairAddress);
        address tokenAddress;
        if (tokenType == ILSSVMPairFactoryLike.PairTokenType.ETH) {
            tokenAddress = address(0);
        } else {
            tokenAddress = address(LSSVMPairERC20(pairAddress).token());
        }
        ILSSVMPairFactoryLike.PairNFTType nftType = factory.getPairNFTType(pairAddress);
        BasicHeap.Heap storage heap = (nftType == ILSSVMPairFactoryLike.PairNFTType.ERC721)
            ? _sellHeap[LSSVMPair(pairAddress).nft()][tokenAddress]
            : _sellHeapERC1155[LSSVMPair(pairAddress).nft()][LSSVMPairERC1155(pairAddress).nftId()][tokenAddress];
        return uint256((heap.getValueOf({id: pairAddress})));
    }

    function getBestBuyQuoteForERC721(address collection, address tokenAddress) external view returns (uint256) {
        return uint256(-(_buyHeap[collection][tokenAddress].getValueOfRoot()));
    }

    function getAllBuyQuotesForERC721(address collection, address tokenAddress)
        external
        view
        returns (BasicHeap.Account[] memory)
    {
        return _buyHeap[collection][tokenAddress].accountList();
    }

    function getBestSellQuoteForERC721(address collection, address tokenAddress) external view returns (uint256) {
        return uint256((_sellHeap[collection][tokenAddress].getValueOfRoot()));
    }

    function getAllSellQuotesForERC721(address collection, address tokenAddress)
        external
        view
        returns (BasicHeap.Account[] memory)
    {
        return _sellHeap[collection][tokenAddress].accountList();
    }

    function getBuyQuoteForERC1155(address collection, uint256 nftId, address tokenAddress)
        external
        view
        returns (uint256)
    {
        return uint256(-(_buyHeapERC1155[collection][nftId][tokenAddress].getValueOfRoot()));
    }

    function getAllBuyQuotesForERC1155(address collection, uint256 nftId, address tokenAddress)
        external
        view
        returns (BasicHeap.Account[] memory)
    {
        return _buyHeapERC1155[collection][nftId][tokenAddress].accountList();
    }

    function getSellQuoteForERC1155(address collection, uint256 nftId, address tokenAddress)
        external
        view
        returns (uint256)
    {
        return uint256((_sellHeapERC1155[collection][nftId][tokenAddress].getValueOfRoot()));
    }

    function getAllSellQuotesForERC1155(address collection, uint256 nftId, address tokenAddress)
        external
        view
        returns (BasicHeap.Account[] memory)
    {
        return _sellHeapERC1155[collection][nftId][tokenAddress].accountList();
    }

    /// -----------------------------------------------------------------------
    /// Hooks
    /// -----------------------------------------------------------------------

    function afterNewPair() external onlyValidPair(msg.sender) {
        _updateQuotesOfPair(msg.sender);
    }

    function afterSwapNFTInPair(uint256, uint256, uint256, uint256[] calldata) external onlyValidPair(msg.sender) {
        _updateQuotesOfPair(msg.sender);
    }

    function afterSwapNFTOutPair(uint256, uint256, uint256, uint256[] calldata) external onlyValidPair(msg.sender) {
        _updateQuotesOfPair(msg.sender);
    }

    function afterDeltaUpdate(uint128, uint128) external onlyValidPair(msg.sender) {
        _updateQuotesOfPair(msg.sender);
    }

    function afterSpotPriceUpdate(uint128, uint128) external onlyValidPair(msg.sender) {
        _updateQuotesOfPair(msg.sender);
    }

    function afterFeeUpdate(uint96, uint96) external onlyValidPair(msg.sender) {
        _updateQuotesOfPair(msg.sender);
    }

    function afterNFTWithdrawal(uint256[] calldata) external onlyValidPair(msg.sender) {
        _updateQuotesOfPair(msg.sender);
    }

    function afterTokenWithdrawal(uint256) external onlyValidPair(msg.sender) {
        _updateQuotesOfPair(msg.sender);
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    function addCurve(address a) external onlyOwner {
        allowedCurves[a] = true;
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _updateQuotesOfPair(address pairAddress) internal {
        LSSVMPair pair = LSSVMPair(pairAddress);
        address collection = address(pair.nft());
        LSSVMPair.PoolType poolType = pair.poolType();
        ILSSVMPairFactoryLike.PairNFTType nftType = factory.getPairNFTType(pairAddress);

        // Update buy quote
        if (poolType != LSSVMPair.PoolType.TOKEN) {
            (CurveErrorCodes.Error errorCode,,, uint256 quoteAmount,,) = pair.bondingCurve().getBuyInfo({
                spotPrice: pair.spotPrice(),
                delta: pair.delta(),
                numItems: 1,
                feeMultiplier: pair.fee(),
                protocolFeeMultiplier: factory.protocolFeeMultiplier()
            });
            (BasicHeap.Heap storage buyHeap, uint256 nftBalance) =
                _getBuyHeapAndNftBalanceOfPair(pairAddress, collection, nftType);
            if (errorCode == CurveErrorCodes.Error.OK && nftBalance >= 1) {
                buyHeap.update({id: pairAddress, value: -quoteAmount.toInt256()}); // negate amount to use min heap as max heap
            } else if (buyHeap.containsAccount({id: pairAddress})) {
                buyHeap.remove({id: pairAddress});
            }
        }

        // Update sell quote
        if (poolType != LSSVMPair.PoolType.NFT) {
            (CurveErrorCodes.Error errorCode,,, uint256 quoteAmount,,) = pair.bondingCurve().getSellInfo({
                spotPrice: pair.spotPrice(),
                delta: pair.delta(),
                numItems: 1,
                feeMultiplier: pair.fee(),
                protocolFeeMultiplier: factory.protocolFeeMultiplier()
            });
            (BasicHeap.Heap storage sellHeap, uint256 tokenBalance) =
                _getSellHeapAndTokenBalanceOfPair(pairAddress, collection, nftType);
            if (errorCode == CurveErrorCodes.Error.OK && tokenBalance >= quoteAmount) {
                sellHeap.update({id: pairAddress, value: quoteAmount.toInt256()});
            } else if (sellHeap.containsAccount({id: pairAddress})) {
                sellHeap.remove({id: pairAddress});
            }
        }
    }

    function _getSellHeapAndTokenBalanceOfPair(
        address pairAddress,
        address collection,
        ILSSVMPairFactoryLike.PairNFTType nftType
    ) internal view returns (BasicHeap.Heap storage heap, uint256 balance) {
        ILSSVMPairFactoryLike.PairTokenType tokenType = factory.getPairTokenType(pairAddress);
        address tokenAddress;
        if (tokenType == ILSSVMPairFactoryLike.PairTokenType.ETH) {
            tokenAddress = address(0);
        } else {
            tokenAddress = address(LSSVMPairERC20(pairAddress).token());
        }

        if (nftType == ILSSVMPairFactoryLike.PairNFTType.ERC721) {
            heap = _sellHeap[collection][tokenAddress];
        } else {
            heap = _sellHeapERC1155[collection][LSSVMPairERC1155(pairAddress).nftId()][tokenAddress];
        }
        if (tokenType == ILSSVMPairFactoryLike.PairTokenType.ETH) {
            balance = pairAddress.balance;
        } else {
            balance = LSSVMPairERC20(pairAddress).token().balanceOf(pairAddress);
        }
    }

    function _getBuyHeapAndNftBalanceOfPair(
        address pairAddress,
        address collection,
        ILSSVMPairFactoryLike.PairNFTType nftType
    ) internal view returns (BasicHeap.Heap storage heap, uint256 balance) {
        ILSSVMPairFactoryLike.PairTokenType tokenType = factory.getPairTokenType(pairAddress);
        address tokenAddress;
        if (tokenType == ILSSVMPairFactoryLike.PairTokenType.ETH) {
            tokenAddress = address(0);
        } else {
            tokenAddress = address(LSSVMPairERC20(pairAddress).token());
        }
        if (nftType == ILSSVMPairFactoryLike.PairNFTType.ERC721) {
            return (_buyHeap[collection][tokenAddress], IERC721(collection).balanceOf(pairAddress));
        } else {
            uint256 nftId = LSSVMPairERC1155(pairAddress).nftId();
            return
                (_buyHeapERC1155[collection][nftId][tokenAddress], IERC1155(collection).balanceOf(pairAddress, nftId));
        }
    }
}
