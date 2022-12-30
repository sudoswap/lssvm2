// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface ILSSVMPair {
    enum PoolType {
        TOKEN,
        NFT,
        TRADE
    }

    function getAssetRecipient() external returns (address);

    function changeAssetRecipient(address payable newRecipient) external;

    function poolType() external returns (PoolType);

    function token() external returns (ERC20 _token);
}
