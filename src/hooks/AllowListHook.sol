// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IPairHooks} from "./IPairHooks.sol";
import {LSSVMPair} from "../LSSVMPair.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Owned} from "solmate/auth/Owned.sol";

contract AllowListHook is IPairHooks, Owned {

    mapping(uint256 => address) public allowList;
    error AllowListHook__WrongOwner();

    constructor() Owned(msg.sender) {}

    // Owner function to modify the allow list
    function modifyAllowList(uint256[] calldata ids, address[] calldata allowedBuyers) external onlyOwner {
        for (uint i; i < ids.length; ++i) {
          allowList[ids[i]] = allowedBuyers[i];
        }
    }

    // Also need to factor in new token balance and new NFT balance during calculations
    function afterSwapNFTOutPair(
        uint256 ,
        uint256 ,
        uint256 ,
        uint256[] calldata _nftsOut
    ) external {
        IERC721 nft = IERC721(LSSVMPair(msg.sender).nft());
        
        // Assert the desired owner is the owner post-swap
        for (uint i; i < _nftsOut.length; ++i) {
            uint256 id = _nftsOut[i];
            address desiredOwner =allowList[id];
            if (nft.ownerOf(id) != desiredOwner) {
                revert AllowListHook__WrongOwner();
            }
        }
    }

    // Stub implementations after here
    function afterNewPair() external {
    }
    function afterSwapNFTInPair(
        uint256 _tokensOut,
        uint256 _tokensOutProtocolFee,
        uint256 _tokensOutRoyalty,
        uint256[] calldata _nftsIn
    ) external {
    }
    function afterDeltaUpdate(uint128 _oldDelta, uint128 _newDelta) external {
    }
    function afterSpotPriceUpdate(uint128 _oldSpotPrice, uint128 _newSpotPrice) external {
    }
    function afterFeeUpdate(uint96 _oldFee, uint96 _newFee) external {
    }
    function afterNFTWithdrawal(uint256[] calldata _nftsOut) external {
    }
    function afterTokenWithdrawal(uint256 _tokensOut) external {
    }
    function syncForPair(address pairAddress, uint256 _tokensIn, uint256[] calldata _nftsIn) external {
    }

}