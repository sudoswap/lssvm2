// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ILSSVMPair} from "../ILSSVMPair.sol";
import {OwnableWithTransferCallback} from "../lib/OwnableWithTransferCallback.sol";
import {CurveErrorCodes} from "../bonding-curves/CurveErrorCodes.sol";
import {ICurve} from "../bonding-curves/ICurve.sol";

contract MockPair is ILSSVMPair, OwnableWithTransferCallback {
    constructor() {
        __Ownable_init(msg.sender);
    }

    address constant ASSET_RECIPIENT = address(11111);
    address constant FEE_RECIPIENT = address(22222);
    address constant NFT_ADDRESS = address(33333);
    address constant TOKEN_ADDRESS = address(34264323492);

    function getAssetRecipient() external pure returns (address) {
        return ASSET_RECIPIENT;
    }

    function getFeeRecipient() external pure returns (address) {
        return FEE_RECIPIENT;
    }

    function changeAssetRecipient(address payable newRecipient) public pure {}

    function poolType() external pure returns (PoolType) {
        return ILSSVMPair.PoolType.TRADE;
    }

    function token() external pure returns (ERC20 _token) {
        return ERC20(TOKEN_ADDRESS);
    }

    function changeFee(uint96 newFee) external pure {}

    function changeSpotPrice(uint128 newSpotPrice) external pure {}

    function changeDelta(uint128 newDelta) external pure {}

    function getBuyNFTQuote(uint256 numItems)
        external
        returns (
            CurveErrorCodes.Error error,
            uint256 newSpotPrice,
            uint256 newDelta,
            uint256 inputAmount,
            uint256 protocolFee
        )
    {}

    function getSellNFTQuote(uint256 numNFTs)
        external
        view
        returns (
            CurveErrorCodes.Error error,
            uint256 newSpotPrice,
            uint256 newDelta,
            uint256 outputAmount,
            uint256 protocolFee
        )
    {}

    function bondingCurve() external pure returns (ICurve) {
        return ICurve(TOKEN_ADDRESS);
    }

    function fee() external pure returns (uint96) {
        return 0;
    }

    function nft() external pure returns (IERC721) {
        return IERC721(NFT_ADDRESS);
    }

    function withdrawERC20(ERC20 a, uint256 amount) external {}

    function withdrawERC721(IERC721 a, uint256[] calldata nftIds) external {}
}
