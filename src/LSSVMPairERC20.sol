// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {LSSVMPair} from "./LSSVMPair.sol";
import {LSSVMRouter} from "./LSSVMRouter.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
/**
 * @title An NFT/Token pair where the token is an ERC20
 *     @author boredGenius and 0xmons
 */
abstract contract LSSVMPairERC20 is LSSVMPair {
    using SafeTransferLib for ERC20;

    /**
     * @notice Returns the ERC20 token associated with the pair
     *     @dev See LSSVMPairCloner for an explanation on how this works
     *     @dev The last 20 bytes of the immutable data contain the ERC20 token address
     */
    function token() public pure returns (ERC20 _token) {
        assembly {
            _token := shr(0x60, calldataload(sub(calldatasize(), 20)))
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
        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 royaltyTotal) =
            _calculateRoyalties(assetId, saleAmount);

        // Deduct royalties from sale amount
        unchecked {
            // Safe because we already require saleAmount >= royaltyTotal in _calculateRoyalties()
            saleAmount -= royaltyTotal;
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
            router.pairTransferERC20From(_token, routerCaller, _assetRecipient, saleAmount);

            // Verify token transfer (protect pair against malicious router)
            require(_token.balanceOf(_assetRecipient) - beforeBalance == saleAmount, "Asset recipient not paid");

            // Transfer royalties (if it exists)
            for (uint256 i; i < royaltyRecipients.length;) {
                beforeBalance = _token.balanceOf(royaltyRecipients[i]);
                router.pairTransferERC20From(_token, routerCaller, royaltyRecipients[i], royaltyAmounts[i]);
                require(
                    _token.balanceOf(royaltyRecipients[i]) - beforeBalance == royaltyAmounts[i],
                    "Royalty recipient not paid"
                );
                unchecked {
                    ++i;
                }
            }

            // Take protocol fee (if it exists)
            if (protocolFee != 0) {
                router.pairTransferERC20From(_token, routerCaller, address(_factory), protocolFee);
            }
        } else {
            // Transfer tokens directly
            _token.safeTransferFrom(msg.sender, _assetRecipient, saleAmount);

            // Transfer royalties (if it exists)
            for (uint256 i; i < royaltyRecipients.length;) {
                _token.safeTransferFrom(msg.sender, royaltyRecipients[i], royaltyAmounts[i]);
                unchecked {
                    ++i;
                }
            }

            // Take protocol fee (if it exists)
            if (protocolFee != 0) {
                _token.safeTransferFrom(msg.sender, address(_factory), protocolFee);
            }
        }
        // Send trade fee if it exists, is TRADE pool, and fee recipient != pool address
        if (poolType() == PoolType.TRADE && tradeFeeAmount != 0) {
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
    function _sendTokenOutput(address payable tokenRecipient, uint256 outputAmount) internal override {
        // Send tokens to caller
        if (outputAmount != 0) {
            token().safeTransfer(tokenRecipient, outputAmount);
        }
    }

    /// @inheritdoc LSSVMPair
    function withdrawERC20(ERC20 a, uint256 amount) external override onlyOwner {
        a.safeTransfer(msg.sender, amount);

        if (a == token()) {
            // emit event since it is the pair token
            emit TokenWithdrawal(amount);
        }
    }

    function _preCallCheck(address target) internal pure override {
        require(target != address(token()), "Banned target");
    }
}
