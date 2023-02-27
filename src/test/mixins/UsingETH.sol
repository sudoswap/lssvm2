// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {Configurable} from "./Configurable.sol";
import {RouterCaller} from "./RouterCaller.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {LSSVMPairETH} from "../../LSSVMPairETH.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMPairERC721} from "../../erc721/LSSVMPairERC721.sol";
import {LSSVMPairERC1155} from "../../erc1155/LSSVMPairERC1155.sol";

abstract contract UsingETH is Configurable, RouterCaller {
    function modifyInputAmount(uint256 inputAmount) public pure override returns (uint256) {
        return inputAmount;
    }

    function getBalance(address a) public view override returns (uint256) {
        return a.balance;
    }

    function sendTokens(LSSVMPair pair, uint256 amount) public override {
        payable(address(pair)).transfer(amount);
    }

    function setupPairERC721(
        LSSVMPairFactory factory,
        IERC721 nft,
        ICurve bondingCurve,
        address payable assetRecipient,
        LSSVMPair.PoolType poolType,
        uint128 delta,
        uint96 fee,
        uint128 spotPrice,
        uint256[] memory _idList,
        uint256,
        address
    ) public payable override returns (LSSVMPair) {
        LSSVMPairETH pair = factory.createPairERC721ETH{value: msg.value}(
            nft, bondingCurve, assetRecipient, poolType, delta, fee, spotPrice, address(0), _idList
        );
        return pair;
    }

    function setupPairERC1155(CreateERC1155PairParams memory params) public payable override returns (LSSVMPair) {
        LSSVMPairETH pair = params.factory.createPairERC1155ETH{value: msg.value}(
            params.nft,
            params.bondingCurve,
            params.assetRecipient,
            params.poolType,
            params.delta,
            params.fee,
            params.spotPrice,
            params.nftId,
            params.initialNFTBalance
        );
        return pair;
    }

    function setupPairWithPropertyCheckerERC721(PairCreationParamsWithPropertyCheckerERC721 memory params)
        public
        payable
        override
        returns (LSSVMPairERC721 pair)
    {
        pair = params.factory.createPairERC721ETH{value: msg.value}(
            params.nft,
            params.bondingCurve,
            params.assetRecipient,
            params.poolType,
            params.delta,
            params.fee,
            params.spotPrice,
            params.propertyChecker,
            params._idList
        );
    }

    function withdrawTokens(LSSVMPair pair) public override {
        LSSVMPairETH(payable(address(pair))).withdrawAllETH();
    }

    function withdrawProtocolFees(LSSVMPairFactory factory) public override {
        factory.withdrawETHProtocolFees();
    }

    function swapTokenForSpecificNFTs(
        LSSVMRouter router,
        LSSVMRouter.PairSwapSpecific[] calldata swapList,
        address payable ethRecipient,
        address nftRecipient,
        uint256 deadline,
        uint256
    ) public payable override returns (uint256) {
        return router.swapETHForSpecificNFTs{value: msg.value}(swapList, ethRecipient, nftRecipient, deadline);
    }

    function swapNFTsForSpecificNFTsThroughToken(
        LSSVMRouter router,
        LSSVMRouter.NFTsForSpecificNFTsTrade calldata trade,
        uint256 minOutput,
        address payable ethRecipient,
        address nftRecipient,
        uint256 deadline,
        uint256
    ) public payable override returns (uint256) {
        return router.swapNFTsForSpecificNFTsThroughETH{value: msg.value}(
            trade, minOutput, ethRecipient, nftRecipient, deadline
        );
    }

    function robustSwapTokenForSpecificNFTs(
        LSSVMRouter router,
        LSSVMRouter.RobustPairSwapSpecific[] calldata swapList,
        address payable ethRecipient,
        address nftRecipient,
        uint256 deadline,
        uint256
    ) public payable override returns (uint256) {
        return router.robustSwapETHForSpecificNFTs{value: msg.value}(swapList, ethRecipient, nftRecipient, deadline);
    }

    function robustSwapTokenForSpecificNFTsAndNFTsForTokens(
        LSSVMRouter router,
        LSSVMRouter.RobustPairNFTsFoTokenAndTokenforNFTsTrade calldata params
    ) public payable override returns (uint256, uint256) {
        return router.robustSwapETHForSpecificNFTsAndNFTsToToken{value: msg.value}(params);
    }
}
