// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {LSSVMPair} from "../LSSVMPair.sol";
import {ICurve} from "../bonding-curves/ICurve.sol";

interface IPairHooks {
    function afterNewPair() external;

    // Also need to factor in new token balance and new NFT balance during calculations
    function afterSwapNFTInPair(
        uint256 _tokensOut,
        uint256 _tokensOutProtocolFee,
        uint256 _tokensOutRoyalty,
        uint256[] calldata _nftsIn
    ) external;

    // Also need to factor in new token balance and new NFT balance during calculations
    function afterSwapNFTOutPair(
        uint256 _tokensIn,
        uint256 _tokensInProtocolFee,
        uint256 _tokensInRoyalty,
        uint256[] calldata _nftsOut
    ) external;

    function afterDeltaUpdate(uint128 _oldDelta, uint128 _newDelta) external;

    function afterSpotPriceUpdate(uint128 _oldSpotPrice, uint128 _newSpotPrice) external;

    function afterFeeUpdate(uint96 _oldFee, uint96 _newFee) external;

    // Also need to factor in the new NFT balance
    function afterNFTWithdrawal(uint256[] calldata _nftsOut) external;

    // Also need to factor in the new token balance
    function afterTokenWithdrawal(uint256 _tokensOut) external;

    // NFT Deposit and Token Deposit are called from the Factory, not the Pair
    // So instead we have this catch-all for letting external callers (like the Factory) update state for a given pair
    function syncForPair(address pairAddress, uint256 _tokensIn, uint256[] calldata _nftsIn) external;
}
