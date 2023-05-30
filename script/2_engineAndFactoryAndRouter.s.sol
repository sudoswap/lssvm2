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

contract engineAndFactoryAndRouterDeploy is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() external returns (
            LSSVMPairERC721ETH erc721ETHTemplate,
            LSSVMPairERC721ERC20 erc721ERC20Template,
            LSSVMPairERC1155ETH erc1155ETHTemplate,
            LSSVMPairERC1155ERC20 erc1155ERC20Template,
            LSSVMPairFactory factory,
            RoyaltyEngine royaltyEngine,
            VeryFastRouter router
        ) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address royaltyRegistry = vm.envAddress("ROYALTY_REGISTRY");
        vm.startBroadcast(deployerPrivateKey);
        require(ERC165Checker.supportsInterface(royaltyRegistry, type(IRoyaltyRegistry).interfaceId));

        // Deploy royalty engine
        royaltyEngine = RoyaltyEngine(
            create3.deploy(
                getCreate3ContractSalt("RoyaltyEngine"),
                bytes.concat(type(RoyaltyEngine).creationCode, abi.encode(royaltyRegistry))
            )
        );

        // deploy factory
        bytes memory factoryConstructorArgs;
        {
            erc721ETHTemplate = LSSVMPairERC721ETH(
                payable(
                    create3.deploy(
                        getCreate3ContractSalt("LSSVMPairERC721ETH"),
                        bytes.concat(type(LSSVMPairERC721ETH).creationCode, abi.encode(address(royaltyEngine)))
                    )
                )
            );
            erc721ERC20Template = LSSVMPairERC721ERC20(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMPairERC721ERC20"),
                    bytes.concat(type(LSSVMPairERC721ERC20).creationCode, abi.encode(address(royaltyEngine)))
                )
            );
            erc1155ETHTemplate = LSSVMPairERC1155ETH(
                payable(
                    create3.deploy(
                        getCreate3ContractSalt("LSSVMPairERC1155ETH"),
                        bytes.concat(type(LSSVMPairERC1155ETH).creationCode, abi.encode(address(royaltyEngine)))
                    )
                )
            );
            erc1155ERC20Template = LSSVMPairERC1155ERC20(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMPairERC1155ERC20"),
                    bytes.concat(type(LSSVMPairERC1155ERC20).creationCode, abi.encode(address(royaltyEngine)))
                )
            );
            address deployer = vm.addr(deployerPrivateKey);
            factoryConstructorArgs = abi.encode(
                erc721ETHTemplate,
                erc721ERC20Template,
                erc1155ETHTemplate,
                erc1155ERC20Template,
                vm.envAddress("PROTOCOL_FEE_RECIPIENT"),
                vm.envUint("PROTOCOL_FEE"),
                deployer
            );
        }
        factory = LSSVMPairFactory(
            payable(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMPairFactory"),
                    bytes.concat(type(LSSVMPairFactory).creationCode, factoryConstructorArgs)
                )
            )
        );

        // deploy router
        router = VeryFastRouter(
            payable(
                create3.deploy(
                    getCreate3ContractSalt("VeryFastRouter"),
                    bytes.concat(type(VeryFastRouter).creationCode, abi.encode(factory))
                )
            )
        );

        vm.stopBroadcast();
    }
}