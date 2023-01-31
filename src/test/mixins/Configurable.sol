// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {LSSVMPair} from "../../LSSVMPair.sol";
import {Test721} from "../../mocks/Test721.sol";
import {ICurve} from "../../bonding-curves/ICurve.sol";
import {LSSVMPairFactory} from "../../LSSVMPairFactory.sol";
import {LSSVMPairERC721} from "../../erc721/LSSVMPairERC721.sol";
import {IERC721Mintable} from "../interfaces/IERC721Mintable.sol";
import {LSSVMPairERC1155} from "../../erc1155/LSSVMPairERC1155.sol";
import {LSSVMPairERC721ETH} from "../../erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC1155ETH} from "../../erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "../../erc721/LSSVMPairERC721ERC20.sol";
import {LSSVMPairERC1155ERC20} from "../../erc1155/LSSVMPairERC1155ERC20.sol";

abstract contract Configurable {
    function setupFactory(RoyaltyRegistry royaltyRegistry, address payable feeRecipient)
        public
        virtual
        returns (LSSVMPairFactory factory)
    {
        LSSVMPairERC721ETH erc721ETHTemplate = new LSSVMPairERC721ETH(royaltyRegistry);
        LSSVMPairERC721ERC20 erc721ERC20Template = new LSSVMPairERC721ERC20(royaltyRegistry);
        LSSVMPairERC1155ETH erc1155ETHTemplate = new LSSVMPairERC1155ETH(royaltyRegistry);
        LSSVMPairERC1155ERC20 erc1155ERC20Template = new LSSVMPairERC1155ERC20(royaltyRegistry);
        factory = new LSSVMPairFactory(
            erc721ETHTemplate,
            erc721ERC20Template,
            erc1155ETHTemplate,
            erc1155ERC20Template,
            feeRecipient,
            0, // Zero protocol fee to make calculations easier
            address(this)
        );
    }

    function setupFactory(RoyaltyRegistry royaltyRegistry, address payable feeRecipient, uint256 protocolFeeMultiplier)
        public
        virtual
        returns (LSSVMPairFactory factory)
    {
        LSSVMPairERC721ETH erc721ETHTemplate = new LSSVMPairERC721ETH(royaltyRegistry);
        LSSVMPairERC721ERC20 erc721ERC20Template = new LSSVMPairERC721ERC20(royaltyRegistry);
        LSSVMPairERC1155ETH erc1155ETHTemplate = new LSSVMPairERC1155ETH(royaltyRegistry);
        LSSVMPairERC1155ERC20 erc1155ERC20Template = new LSSVMPairERC1155ERC20(royaltyRegistry);
        factory = new LSSVMPairFactory(
            erc721ETHTemplate,
            erc721ERC20Template,
            erc1155ETHTemplate,
            erc1155ERC20Template,
            feeRecipient,
            protocolFeeMultiplier,
            address(this)
        );
    }

    function getBalance(address a) public virtual returns (uint256);

    function setupPair(
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
        address routerAddress /* Yes, this is weird, but due to how we encapsulate state for a Pair's ERC20 token, this is an easy way to set approval for the router.*/
    ) public payable virtual returns (LSSVMPair);

    struct PairCreationParamsWithPropertyChecker {
        LSSVMPairFactory factory;
        IERC721 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPair.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        uint256[] _idList;
        uint256 initialTokenBalance;
        address routerAddress;
        address propertyChecker;
    }

    function setupPairWithPropertyChecker(PairCreationParamsWithPropertyChecker memory params)
        public
        payable
        virtual
        returns (LSSVMPairERC721);

    function setupCurve() public virtual returns (ICurve);

    function setup721() public virtual returns (IERC721Mintable) {
        return IERC721Mintable(address(new Test721()));
    }

    function modifyInputAmount(uint256 inputAmount) public virtual returns (uint256);

    function modifyDelta(uint64 delta) public virtual returns (uint64);

    function modifySpotPrice(uint56 spotPrice) public virtual returns (uint56);

    function sendTokens(LSSVMPair pair, uint256 amount) public virtual;

    function withdrawTokens(LSSVMPair pair) public virtual;

    function withdrawProtocolFees(LSSVMPairFactory factory) public virtual;

    function getParamsForPartialFillTest() public virtual returns (uint128 spotPrice, uint128 delta);

    function getParamsForAdjustingPriceToBuy(LSSVMPair pair, uint256 percentage, bool isIncrease)
        public
        virtual
        returns (uint128 spotPrice, uint128 delta);

    receive() external payable {}
}
