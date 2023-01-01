// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {StandardAgreement} from "./StandardAgreement.sol";

contract StandardAgreementFactory {
    using ClonesWithImmutableArgs for address;
    
    event NewAgreement(address agreementAddress);

    uint256 constant BASE = 10_000;

    StandardAgreement immutable standardAgreementImplementation;

    constructor(StandardAgreement _standardAgreementImplementation) {
      standardAgreementImplementation = _standardAgreementImplementation;
    }

    function createAgreement(
      address payable agreementFeeRecipient,
      uint256 ethCost,
      uint64 secDuration,
      uint64 feeSplitBps,
      uint64 royaltyBps
    ) public returns (StandardAgreement agreement) {
      require(royaltyBps <= (BASE/10), "Max 10% for modified royalty bps");
      require(feeSplitBps <= BASE, "Max 100% for trade fee bps split");
      bytes memory data = abi.encodePacked(ethCost, secDuration, feeSplitBps, royaltyBps);
      agreement = StandardAgreement(address(standardAgreementImplementation).clone(data));
      agreement.initialize(msg.sender, agreementFeeRecipient);
      emit NewAgreement(address(agreement));
    }
}
