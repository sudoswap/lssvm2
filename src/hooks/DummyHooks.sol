// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IPairHooks} from "./IPairHooks.sol";

contract DummyHooks is IPairHooks {
    event e_afterNewPair();
    event e_afterSwapNFTInPair(
        uint256 _tokensOut, uint256 _tokensOutProtocolFee, uint256 _tokensOutRoyalty, uint256[] _nftsIn
    );
    event e_afterSwapNFTOutPair(
        uint256 _tokensIn, uint256 _tokensInProtocolFee, uint256 _tokensInRoyalty, uint256[] _nftsOut
    );
    event e_afterDeltaUpdate(uint128 _oldDelta, uint128 _newDelta);
    event e_afterSpotPriceUpdate(uint128 _oldSpotPrice, uint128 _newSpotPrice);
    event e_afterFeeUpdate(uint96 _oldFee, uint96 _newFee);
    event e_afterNFTWithdrawal(uint256[] _nftsOut);
    event e_afterTokenWithdrawal(uint256 _tokensOut);
    event e_syncForPair(address pairAddress, uint256 _tokensIn, uint256[] _nftsIn);

    function afterNewPair() external {
        emit e_afterNewPair();
    }

    // Also need to factor in new token balance and new NFT balance during calculations
    function afterSwapNFTInPair(
        uint256 _tokensOut,
        uint256 _tokensOutProtocolFee,
        uint256 _tokensOutRoyalty,
        uint256[] calldata _nftsIn
    ) external {
        emit e_afterSwapNFTInPair(_tokensOut, _tokensOutProtocolFee, _tokensOutRoyalty, _nftsIn);
    }

    // Also need to factor in new token balance and new NFT balance during calculations
    function afterSwapNFTOutPair(
        uint256 _tokensIn,
        uint256 _tokensInProtocolFee,
        uint256 _tokensInRoyalty,
        uint256[] calldata _nftsOut
    ) external {
        emit e_afterSwapNFTOutPair(_tokensIn, _tokensInProtocolFee, _tokensInRoyalty, _nftsOut);
    }

    function afterDeltaUpdate(uint128 _oldDelta, uint128 _newDelta) external {
        emit e_afterDeltaUpdate(_oldDelta, _newDelta);
    }

    function afterSpotPriceUpdate(uint128 _oldSpotPrice, uint128 _newSpotPrice) external {
        emit e_afterSpotPriceUpdate(_oldSpotPrice, _newSpotPrice);
    }

    function afterFeeUpdate(uint96 _oldFee, uint96 _newFee) external {
        emit e_afterFeeUpdate(_oldFee, _newFee);
    }

    // Also need to factor in the new NFT balance
    function afterNFTWithdrawal(uint256[] calldata _nftsOut) external {
        emit e_afterNFTWithdrawal(_nftsOut);
    }

    // Also need to factor in the new token balance
    function afterTokenWithdrawal(uint256 _tokensOut) external {
        emit e_afterTokenWithdrawal(_tokensOut);
    }

    // NFT Deposit and Token Deposit are called from the Factory, not the Pair
    // So instead we have this catch-all for letting external callers (like the Factory) update state for a given pair
    function syncForPair(address pairAddress, uint256 _tokensIn, uint256[] calldata _nftsIn) external {
        emit e_syncForPair(pairAddress, _tokensIn, _nftsIn);
    }
}
