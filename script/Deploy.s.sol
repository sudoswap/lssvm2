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

contract DeployScript is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run()
        external
        returns (
            LSSVMPairFactory factory,
            VeryFastRouter router,
            LinearCurve linearCurve,
            ExponentialCurve exponentialCurve,
            XykCurve xykCurve,
            GDACurve gdaCurve,
            RoyaltyEngine royaltyEngine,
            StandardSettingsFactory settingsFactory,
            PropertyCheckerFactory propertyCheckerFactory
        )
    {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address royaltyRegistry = vm.envAddress("ROYALTY_REGISTRY");

        vm.startBroadcast(deployerPrivateKey);

        require(ERC165Checker.supportsInterface(royaltyRegistry, type(IRoyaltyRegistry).interfaceId));

        // royaltyEngine = RoyaltyEngine(
        //     create3.deploy(
        //         getCreate3ContractSalt("RoyaltyEngine"),
        //         bytes.concat(type(RoyaltyEngine).creationCode, abi.encode(royaltyRegistry))
        //     )
        // );
        royaltyEngine = RoyaltyEngine(address(0x13FAF01b9027FAe4572Ef1D3f848597174c7f3F1));

        // deploy factory
        bytes memory factoryConstructorArgs;
        {
            LSSVMPairERC721ETH erc721ETHTemplate = LSSVMPairERC721ETH(
                payable(
                    create3.deploy(
                        getCreate3ContractSalt("LSSVMPairERC721ETH"),
                        bytes.concat(type(LSSVMPairERC721ETH).creationCode, abi.encode(address(royaltyEngine)))
                    )
                )
            );
            LSSVMPairERC721ERC20 erc721ERC20Template = LSSVMPairERC721ERC20(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMPairERC721ERC20"),
                    bytes.concat(type(LSSVMPairERC721ERC20).creationCode, abi.encode(address(royaltyEngine)))
                )
            );
            LSSVMPairERC1155ETH erc1155ETHTemplate = LSSVMPairERC1155ETH(
                payable(
                    create3.deploy(
                        getCreate3ContractSalt("LSSVMPairERC1155ETH"),
                        bytes.concat(type(LSSVMPairERC1155ETH).creationCode, abi.encode(address(royaltyEngine)))
                    )
                )
            );
            LSSVMPairERC1155ERC20 erc1155ERC20Template = LSSVMPairERC1155ERC20(
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

        // deploy bonding curves
        // linearCurve = LinearCurve(create3.deploy(getCreate3ContractSalt("LinearCurve"), type(LinearCurve).creationCode));
        // exponentialCurve = ExponentialCurve(
        //     create3.deploy(getCreate3ContractSalt("ExponentialCurve"), type(ExponentialCurve).creationCode)
        // );
        // xykCurve = XykCurve(create3.deploy(getCreate3ContractSalt("XykCurve"), type(XykCurve).creationCode));
        linearCurve = LinearCurve(address(0x2b876A902fe11fb6fAD01DF3ee122B9b784c9A84));
        exponentialCurve = ExponentialCurve(address(0xcEFfc28d19878917fC933A2b4688f24810AF6F65));
        xykCurve = XykCurve(address(0xcEc01d4e17c349c494F1acda4E411532E46F9196));
        gdaCurve = GDACurve(create3.deploy(getCreate3ContractSalt("GDACurve"), type(GDACurve).creationCode));

        // whitelist bonding curves
        factory.setBondingCurveAllowed(linearCurve, true);
        factory.setBondingCurveAllowed(exponentialCurve, true);
        factory.setBondingCurveAllowed(xykCurve, true);
        factory.setBondingCurveAllowed(gdaCurve, true);

        // deploy router
        router = VeryFastRouter(
            payable(
                create3.deploy(
                    getCreate3ContractSalt("VeryFastRouter"),
                    bytes.concat(type(VeryFastRouter).creationCode, abi.encode(factory))
                )
            )
        );

        // whitelist router
        factory.setRouterAllowed(LSSVMRouter(payable(address(router))), true);

        // deploy settings factory
        settingsFactory = deploySettingsFactory(factory);

        // deploy property checker factory
        propertyCheckerFactory = deployPropertyCheckerFactory();

        // transfer factory ownership
        {
            address owner = vm.envAddress("OWNER");
            factory.transferOwnership(owner);
        }
        vm.stopBroadcast();
    }

    function deploySettingsFactory(ILSSVMPairFactoryLike factory)
        internal
        returns (StandardSettingsFactory settingsFactory)
    {
        Splitter splitterImplementation =
            Splitter(payable(create3.deploy(getCreate3ContractSalt("Splitter"), type(Splitter).creationCode)));
        StandardSettings settingsImplementation = StandardSettings(
            create3.deploy(
                getCreate3ContractSalt("StandardSettings"),
                bytes.concat(type(StandardSettings).creationCode, abi.encode(splitterImplementation, factory))
            )
        );
        settingsFactory = StandardSettingsFactory(
            create3.deploy(
                getCreate3ContractSalt("StandardSettingsFactory"),
                bytes.concat(type(StandardSettingsFactory).creationCode, abi.encode(settingsImplementation))
            )
        );
    }

    function deployPropertyCheckerFactory() internal returns (PropertyCheckerFactory propertyCheckerFactory) {
        MerklePropertyChecker merklePropertyChecker = MerklePropertyChecker(
            create3.deploy(
                getCreate3ContractSalt("MerklePropertyChecker"), bytes.concat(type(MerklePropertyChecker).creationCode)
            )
        );
        RangePropertyChecker rangePropertyChecker = RangePropertyChecker(
            create3.deploy(
                getCreate3ContractSalt("RangePropertyChecker"), bytes.concat(type(RangePropertyChecker).creationCode)
            )
        );
        propertyCheckerFactory = PropertyCheckerFactory(
            create3.deploy(
                getCreate3ContractSalt("PropertyCheckerFactory"),
                bytes.concat(
                    type(PropertyCheckerFactory).creationCode, abi.encode(merklePropertyChecker, rangePropertyChecker)
                )
            )
        );
    }
}
