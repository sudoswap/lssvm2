// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {LSSVMPair} from "./LSSVMPair.sol";
import {LSSVMRouter} from "./LSSVMRouter.sol";
import {ICurve} from "./bonding-curves/ICurve.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {CurveErrorCodes} from "./bonding-curves/CurveErrorCodes.sol";

/**
 * @title An NFT/Token pair where the token is an ERC20
 *     @author boredGenius and 0xmons
 */
contract LSSVMPairERC20 is LSSVMPair {
    using SafeTransferLib for ERC20;

    uint256 internal constant IMMUTABLE_PARAMS_LENGTH = 101;

    constructor(IRoyaltyRegistry royaltyRegistry) LSSVMPair(royaltyRegistry) {}

    /**
     * @inheritdoc LSSVMPair
     */
    function pairVariant() public pure override returns (ILSSVMPairFactoryLike.PairVariant) {
        return ILSSVMPairFactoryLike.PairVariant.ERC20;
    }

    /**
     * @notice Returns the ERC20 token associated with the pair
     *     @dev See LSSVMPairCloner for an explanation on how this works
     */
    function token() public pure returns (ERC20 _token) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _token := shr(0x60, calldataload(add(sub(calldatasize(), paramsLength), 81)))
        }
    }

    /// @inheritdoc LSSVMPair
    function _pullTokenInputAndPayProtocolFee(
        uint256 assetId,
        uint256 inputAmount,
        uint256 tradeFeeAmount,
        bool isRouter,
        address routerCaller,
        ILSSVMPairFactoryLike _factory,
        uint256 protocolFee
    ) internal override {
        require(msg.value == 0, "ERC20 pair");

        ERC20 _token = token();
        address _assetRecipient = getAssetRecipient();

        // Compute royalties
        uint256 saleAmount = inputAmount - protocolFee;
        (address royaltyRecipient, uint256 royaltyAmount) = _calculateRoyalties(assetId, saleAmount);

        // Deduct royalties from sale amount
        unchecked {
            // Safe because we already require saleAmount >= royaltyAmount in _calculateRoyalties()
            saleAmount -= royaltyAmount;
        }

        // Transfer tokens
        if (isRouter) {
            // Verify if router is allowed
            LSSVMRouter router = LSSVMRouter(payable(msg.sender));

            // Locally scoped to avoid stack too deep
            {
                (bool routerAllowed,) = _factory.routerStatus(router);
                require(routerAllowed, "Not router");
            }

            // Cache state and then call router to transfer tokens from user
            uint256 beforeBalance = _token.balanceOf(_assetRecipient);
            router.pairTransferERC20From(_token, routerCaller, _assetRecipient, saleAmount, pairVariant());

            // Verify token transfer (protect pair against malicious router)
            require(_token.balanceOf(_assetRecipient) - beforeBalance == saleAmount, "ERC20 not transferred in");

            // Transfer royalties (if it exists)
            if (royaltyAmount != 0) {
                router.pairTransferERC20From(_token, routerCaller, royaltyRecipient, royaltyAmount, pairVariant());
            }

            // Take protocol fee (if it exists)
            if (protocolFee != 0) {
                router.pairTransferERC20From(_token, routerCaller, address(_factory), protocolFee, pairVariant());
            }
        } else {
            // Transfer tokens directly
            _token.safeTransferFrom(msg.sender, _assetRecipient, saleAmount);

            // Transfer royalties (if it exists)
            if (royaltyAmount != 0) {
                _token.safeTransferFrom(msg.sender, royaltyRecipient, royaltyAmount);
            }

            // Take protocol fee (if it exists)
            if (protocolFee != 0) {
                _token.safeTransferFrom(msg.sender, address(_factory), protocolFee);
            }
        }
        // Send trade fee if it exists, is TRADE pool, and fee recipient != pool address
        if (poolType() == PoolType.TRADE && tradeFeeAmount > 0) {
            address payable _feeRecipient = getFeeRecipient();
            if (_feeRecipient != _assetRecipient) {
                _token.safeTransfer(_feeRecipient, tradeFeeAmount);
            }
        }
    }

    /// @inheritdoc LSSVMPair
    function _refundTokenToSender(uint256 inputAmount) internal override {
        // Do nothing since we transferred the exact input amount
    }

    /// @inheritdoc LSSVMPair
    function _payProtocolFeeFromPair(ILSSVMPairFactoryLike _factory, uint256 protocolFee) internal override {
        // Take protocol fee (if it exists)
        if (protocolFee != 0) {
            ERC20 _token = token();
            _token.safeTransfer(address(_factory), protocolFee);
        }
    }

    /// @inheritdoc LSSVMPair
    function _sendTokenOutput(address payable tokenRecipient, uint256 outputAmount) internal override {
        // Send tokens to caller
        if (outputAmount != 0) {
            token().safeTransfer(tokenRecipient, outputAmount);
        }
    }

    /// @inheritdoc LSSVMPair
    /// @dev see LSSVMPairCloner for params length calculation
    function _immutableParamsLength() internal pure override returns (uint256) {
        return IMMUTABLE_PARAMS_LENGTH;
    }

    /// @inheritdoc LSSVMPair
    function withdrawERC20(ERC20 a, uint256 amount) external override onlyOwner {
        a.safeTransfer(msg.sender, amount);

        if (a == token()) {
            // emit event since it is the pair token
            emit TokenWithdrawal(amount);
        }
    }
}
