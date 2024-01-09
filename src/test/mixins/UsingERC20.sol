// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {Test20} from "../../mocks/Test20.sol";
import {Configurable} from "./Configurable.sol";
import {RouterCaller} from "./RouterCaller.sol";
import {LSSVMRouter} from "../../LSSVMRouter.sol";
import {IMintable} from "../interfaces/IMintable.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LSSVMPairERC20} from "../../LSSVMPairERC20.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMPairERC721} from "../../erc721/LSSVMPairERC721.sol";
import {LSSVMPairERC1155} from "../../erc1155/LSSVMPairERC1155.sol";

abstract contract UsingERC20 is Configurable, RouterCaller {
    using SafeTransferLib for ERC20;

    ERC20 test20;

    function modifyInputAmount(uint256) public pure override returns (uint256) {
        return 0;
    }

    function getBalance(address a) public view override returns (uint256) {
        return test20.balanceOf(a);
    }

    function sendTokens(LSSVMPair pair, uint256 amount) public override {
        test20.safeTransfer(address(pair), amount);
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
        uint256 initialTokenBalance,
        address routerAddress
    ) public payable override returns (LSSVMPair) {
        // create ERC20 token if not already deployed
        if (address(test20) == address(0)) {
            test20 = new Test20();
        }

        // set approvals for factory and router
        test20.approve(address(factory), type(uint256).max);
        test20.approve(routerAddress, type(uint256).max);

        // mint enough tokens to caller
        IMintable(address(test20)).mint(address(this), 1000 ether);

        // initialize the pair
        LSSVMPair pair = factory.createPairERC721ERC20(
            LSSVMPairFactory.CreateERC721ERC20PairParams(
                test20,
                nft,
                bondingCurve,
                assetRecipient,
                poolType,
                delta,
                fee,
                spotPrice,
                address(0),
                _idList,
                initialTokenBalance,
                address(0),
                address(0)
            )
        );

        // Set approvals for pair
        test20.approve(address(pair), type(uint256).max);

        return pair;
    }

    function setupPairERC1155(CreateERC1155PairParams memory params) public payable override returns (LSSVMPair) {
        // create ERC20 token if not already deployed
        if (address(test20) == address(0)) {
            test20 = new Test20();
        }

        // set approvals for factory and router
        test20.approve(address(params.factory), type(uint256).max);
        test20.approve(params.routerAddress, type(uint256).max);

        // mint enough tokens to caller
        IMintable(address(test20)).mint(address(this), 1e18 ether);

        // initialize the pair
        LSSVMPair pair = params.factory.createPairERC1155ERC20(
            LSSVMPairFactory.CreateERC1155ERC20PairParams(
                test20,
                params.nft,
                params.bondingCurve,
                params.assetRecipient,
                params.poolType,
                params.delta,
                params.fee,
                params.spotPrice,
                params.nftId,
                params.initialNFTBalance,
                params.initialTokenBalance,
                params.hookAddress,
                address(0)
            )
        );

        // Set approvals for pair for erc20
        test20.approve(address(pair), type(uint256).max);

        return pair;
    }

    function setupPairWithPropertyCheckerERC721(PairCreationParamsWithPropertyCheckerERC721 memory params)
        public
        payable
        override
        returns (LSSVMPairERC721 pair)
    {
        // create ERC20 token if not already deployed
        if (address(test20) == address(0)) {
            test20 = new Test20();
        }

        // set approvals for factory and router
        test20.approve(address(params.factory), type(uint256).max);
        test20.approve(params.routerAddress, type(uint256).max);

        // mint enough tokens to caller
        IMintable(address(test20)).mint(address(this), 1000 ether);

        // initialize the pair
        pair = params.factory.createPairERC721ERC20(
            LSSVMPairFactory.CreateERC721ERC20PairParams(
                test20,
                params.nft,
                params.bondingCurve,
                params.assetRecipient,
                params.poolType,
                params.delta,
                params.fee,
                params.spotPrice,
                params.propertyChecker,
                params._idList,
                params.initialTokenBalance,
                params.hookAddress,
                address(0)
            )
        );

        // Set approvals for pair
        test20.approve(address(pair), type(uint256).max);
    }

    function withdrawTokens(LSSVMPair pair) public override {
        uint256 total = test20.balanceOf(address(pair));
        LSSVMPairERC20(address(pair)).withdrawERC20(test20, total);
    }

    function withdrawProtocolFees(LSSVMPairFactory factory) public override {
        factory.withdrawERC20ProtocolFees(test20, test20.balanceOf(address(factory)));
    }

    function swapTokenForSpecificNFTs(
        LSSVMRouter router,
        LSSVMRouter.PairSwapSpecific[] calldata swapList,
        address payable,
        address nftRecipient,
        uint256 deadline,
        uint256 inputAmount
    ) public payable override returns (uint256) {
        return router.swapERC20ForSpecificNFTs(swapList, inputAmount, nftRecipient, deadline);
    }

    function swapNFTsForSpecificNFTsThroughToken(
        LSSVMRouter router,
        LSSVMRouter.NFTsForSpecificNFTsTrade calldata trade,
        uint256 minOutput,
        address payable,
        address nftRecipient,
        uint256 deadline,
        uint256 inputAmount
    ) public payable override returns (uint256) {
        return router.swapNFTsForSpecificNFTsThroughERC20(trade, inputAmount, minOutput, nftRecipient, deadline);
    }

    function robustSwapTokenForSpecificNFTs(
        LSSVMRouter router,
        LSSVMRouter.RobustPairSwapSpecific[] calldata swapList,
        address payable,
        address nftRecipient,
        uint256 deadline,
        uint256 inputAmount
    ) public payable override returns (uint256) {
        return router.robustSwapERC20ForSpecificNFTs(swapList, inputAmount, nftRecipient, deadline);
    }

    function robustSwapTokenForSpecificNFTsAndNFTsForTokens(
        LSSVMRouter router,
        LSSVMRouter.RobustPairNFTsFoTokenAndTokenforNFTsTrade calldata params
    ) public payable override returns (uint256, uint256) {
        return router.robustSwapERC20ForSpecificNFTsAndNFTsToToken(params);
    }

    function getTokenAddress() public view override returns (address) {
        return address(test20);
    }

    function isETHPool() public pure override returns (bool) {
        return false;
    }
}
