// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {LSSVMPair} from "../src/LSSVMPair.sol";
import {LSSVMRouter} from "../src/LSSVMRouter.sol";
import {CREATE3Script} from "./base/CREATE3Script.sol";
import {RoyaltyEngine} from "../src/RoyaltyEngine.sol";
import {VeryFastRouter} from "../src/VeryFastRouter.sol";
import {XykCurve} from "../src/bonding-curves/XykCurve.sol";
import {GDACurve} from "../src/bonding-curves/GDACurve.sol";
import {LSSVMPairFactory} from "../src/LSSVMPairFactory.sol";
import {ILSSVMPairFactoryLike} from "../src/ILSSVMPairFactoryLike.sol";
import {LinearCurve} from "../src/bonding-curves/LinearCurve.sol";
import {LSSVMPairERC721ETH} from "../src/erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC1155ETH} from "../src/erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "../src/erc721/LSSVMPairERC721ERC20.sol";
import {ExponentialCurve} from "../src/bonding-curves/ExponentialCurve.sol";
import {LSSVMPairERC1155ERC20} from "../src/erc1155/LSSVMPairERC1155ERC20.sol";
import {StandardSettings} from "../src/settings/StandardSettings.sol";
import {StandardSettingsFactory} from "../src/settings/StandardSettingsFactory.sol";
import {Splitter} from "../src/settings/Splitter.sol";
import {PropertyCheckerFactory} from "../src/property-checking/PropertyCheckerFactory.sol";
import {MerklePropertyChecker} from "../src/property-checking/MerklePropertyChecker.sol";
import {RangePropertyChecker} from "../src/property-checking/RangePropertyChecker.sol";

contract BondingCurveDeploy is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() external returns (
            LinearCurve linearCurve,
            ExponentialCurve exponentialCurve,
            XykCurve xykCurve,
            GDACurve gdaCurve
        ) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        // deploy bonding curves
        linearCurve = LinearCurve(create3.deploy(getCreate3ContractSalt("LinearCurve"), type(LinearCurve).creationCode));
        exponentialCurve = ExponentialCurve(
            create3.deploy(getCreate3ContractSalt("ExponentialCurve"), type(ExponentialCurve).creationCode)
        );
        xykCurve = XykCurve(create3.deploy(getCreate3ContractSalt("XykCurve"), type(XykCurve).creationCode));
        gdaCurve = GDACurve(create3.deploy(getCreate3ContractSalt("GDACurve"), type(GDACurve).creationCode));
        vm.stopBroadcast();
    }
}