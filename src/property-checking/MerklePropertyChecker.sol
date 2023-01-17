// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IPropertyChecker} from "./IPropertyChecker.sol";
import {Clone} from "clones-with-immutable-args/Clone.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract RangePropertyChecker is IPropertyChecker, Clone {

    // Immutable params

    /**
     * @return Returns the lower bound of IDs allowed
     */
    function getMerkleRoot() public pure returns (uint256) {
        return _getArgUint256(0);
    }

    function hasProperties(uint256[] calldata ids, bytes calldata params) external pure returns(bool isAllowed) {
        isAllowed = true;
        bytes32 root = bytes32(getMerkleRoot());
        (bytes[] memory proofList) = abi.decode(params, (bytes[]));
        for (uint i; i < ids.length;) {
            bytes32[] memory proof = abi.decode(proofList[i], (bytes32[]));
            if (!MerkleProof.verify(proof, root, bytes32(ids[i]))) {
                return false;
            }
            unchecked {
                ++i;
            }
        }
    }
}