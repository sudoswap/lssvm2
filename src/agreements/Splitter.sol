// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Clone} from "clones-with-immutable-args/Clone.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IStandardAgreement} from "./IStandardAgreement.sol";
import {ILSSVMPair} from "../ILSSVMPair.sol";


contract Splitter is Clone {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address payable;

    uint256 constant BASE = 10_000;

    function getParentAgreement() public pure returns (address) {
        return _getArgAddress(0);
    }

    function getPairAddressForSplitter() public pure returns (address) {
        return _getArgAddress(20);
    }

    function withdrawAllETH() public {
        uint256 ethBalance = address(this).balance;
        withdrawETH(ethBalance);
    }

    function withdrawETH(uint256 ethAmount) public {
        IStandardAgreement parentAgreement = IStandardAgreement(
            getParentAgreement()
        );
        uint256 amtToSendToAgreementFeeRecipient = (parentAgreement
            .getFeeSplitBps() * ethAmount) / BASE;
        parentAgreement.agreementFeeRecipient().safeTransferETH(
            amtToSendToAgreementFeeRecipient
        );
        uint256 amtToSendToPairFeeRecipient = ethAmount -
            amtToSendToAgreementFeeRecipient;
        payable(
            parentAgreement.getPrevFeeRecipientForPair(getPairAddressForSplitter())
        ).safeTransferETH(amtToSendToPairFeeRecipient);
    }

    function withdrawAllBaseQuoteTokens() public {
        ERC20 token = ILSSVMPair(getPairAddressForSplitter()).token();
        uint256 tokenBalance = token.balanceOf(address(this));
        withdrawTokens(token, tokenBalance);
    }

    function withdrawAllTokens(ERC20 token) public {
        uint256 tokenBalance = token.balanceOf(address(this));
        withdrawTokens(token, tokenBalance);
    }

    function withdrawTokens(ERC20 token, uint256 tokenAmount) public {
        IStandardAgreement parentAgreement = IStandardAgreement(
            getParentAgreement()
        );
        uint256 amtToSendToAgreementFeeRecipient = (parentAgreement
            .getFeeSplitBps() * tokenAmount) / BASE;
        token.safeTransfer(
            parentAgreement.agreementFeeRecipient(),
            amtToSendToAgreementFeeRecipient
        );
        uint256 amtToSendToPairFeeRecipient = tokenAmount -
            amtToSendToAgreementFeeRecipient;
        token.safeTransfer(
            parentAgreement.getPrevFeeRecipientForPair(getPairAddressForSplitter()),
            amtToSendToPairFeeRecipient
        );
    }

    fallback() external payable {}
}
