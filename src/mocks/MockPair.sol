// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import {ILSSVMPair} from "../ILSSVMPair.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {OwnableWithTransferCallback} from "../lib/OwnableWithTransferCallback.sol";

contract MockPair is ILSSVMPair,  OwnableWithTransferCallback {

    constructor() {
     __Ownable_init(msg.sender); 
    }

    address constant ASSET_RECIPIENT = address(11111);
    address constant TOKEN_ADDRESS = address(34264323492);

    function getAssetRecipient() external pure returns (address) {
        return ASSET_RECIPIENT;
    }

    function changeAssetRecipient(address payable newRecipient) public pure {}

    function poolType() external pure returns (PoolType) {
        return ILSSVMPair.PoolType.TRADE;
    }

    function token() external pure returns (ERC20 _token) {
        return ERC20(TOKEN_ADDRESS);
    }
}
