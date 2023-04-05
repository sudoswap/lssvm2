// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ISettings} from "../settings/ISettings.sol";

contract MockSettings is ISettings {
    function getFeeSplitBps() external pure returns (uint64) {
        return 1;
    }

    function getRoyaltyInfo(address pairAddress) external view returns (bool, uint96) {
        revert("Failed");
    }

    function settingsFeeRecipient() external returns (address payable) {
        return payable(address(this));
    }

    function getPrevFeeRecipientForPair(address pairAddress) external returns (address) {
        address(this);
    }
}
