// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {MerklePropertyChecker} from "./MerklePropertyChecker.sol";
import {RangePropertyChecker} from "./RangePropertyChecker.sol";

contract PropertyCheckerFactory {
    using ClonesWithImmutableArgs for address;

    event NewMerklePropertyChecker(address a, bytes32 root);
    event NewRangePropertyChecker(address a, uint256 startInclusive, uint256 endInclusive);

    MerklePropertyChecker immutable merklePropertyCheckerImplementation;
    RangePropertyChecker immutable rangePropertyCheckerImplementation;

    constructor(
        MerklePropertyChecker _merklePropertyCheckerImplementation,
        RangePropertyChecker _rangePropertyCheckerImplementation
    ) {
        merklePropertyCheckerImplementation = _merklePropertyCheckerImplementation;
        rangePropertyCheckerImplementation = _rangePropertyCheckerImplementation;
    }

    function createMerklePropertyChecker(bytes32 root) public {
        bytes memory data = abi.encodePacked(uint256(root));
        MerklePropertyChecker checker = MerklePropertyChecker(
            address(merklePropertyCheckerImplementation).clone(data)
        );
        emit NewMerklePropertyChecker(address(checker), root);
    }

    function createRangePropertyChecker(
        uint256 startInclusive,
        uint256 endInclusive
    ) public {
        bytes memory data = abi.encodePacked(startInclusive, endInclusive);
        RangePropertyChecker checker = RangePropertyChecker(address(rangePropertyCheckerImplementation).clone(data));
        emit NewRangePropertyChecker(address(checker), startInclusive, endInclusive);

    }
}
