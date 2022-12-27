// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LSSVMRouter} from "./LSSVMRouter.sol";

interface ILSSVMPairFactoryLike {

    struct Agreement {
      uint96 bps;
      address pairAddress;
    }

    enum PairVariant {
        ETH,
        ERC20
    }

    function protocolFeeMultiplier() external view returns (uint256);

    function protocolFeeRecipient() external view returns (address payable);

    function callAllowed(address target) external view returns (bool);

    function agreementForPair(address pairAddress) external view returns (bool isInAgreement, uint96 bps);

    function routerStatus(LSSVMRouter router) external view returns (bool allowed, bool wasEverAllowed);

    function isPair(address potentialPair, PairVariant variant) external view returns (bool);
}
