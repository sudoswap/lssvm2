// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IStandardAgreement {
    struct PairInAgreement {
        address prevOwner;
        uint96 unlockTime;
        address prevFeeRecipient;
    }

    function getFeeSplitBps() external pure returns (uint64);

    function getRoyaltyInfo(address pairAddress) external view returns (bool, uint96);

    function agreementFeeRecipient() external returns (address payable);

    function getPrevFeeRecipientForPair(address pairAddress) external returns (address);
}
