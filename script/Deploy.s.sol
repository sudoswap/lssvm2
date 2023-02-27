// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LSSVMPair} from "../src/LSSVMPair.sol";
import {LSSVMRouter} from "../src/LSSVMRouter.sol";
import {CREATE3Script} from "./base/CREATE3Script.sol";
import {XykCurve} from "../src/bonding-curves/XykCurve.sol";
import {LSSVMPairFactory} from "../src/LSSVMPairFactory.sol";
import {LinearCurve} from "../src/bonding-curves/LinearCurve.sol";
import {LSSVMPairERC721ETH} from "../src/erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC1155ETH} from "../src/erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "../src/erc721/LSSVMPairERC721ERC20.sol";
import {ExponentialCurve} from "../src/bonding-curves/ExponentialCurve.sol";
import {LSSVMPairERC1155ERC20} from "../src/erc1155/LSSVMPairERC1155ERC20.sol";

contract DeployScript is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run()
        external
        returns (
            LSSVMPairFactory factory,
            LSSVMRouter router,
            LinearCurve linearCurve,
            ExponentialCurve exponentialCurve,
            XykCurve xykCurve
        )
    {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        uint256 protocolFee = vm.envUint("PROTOCOL_FEE");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address royaltyRegistry = vm.envAddress("ROYALTY_REGISTRY");

        vm.startBroadcast(deployerPrivateKey);

        // deploy factory
        bytes memory factoryConstructorArgs;
        {
            LSSVMPairERC721ETH erc721ETHTemplate = LSSVMPairERC721ETH(
                payable(
                    create3.deploy(
                        getCreate3ContractSalt("LSSVMPairERC721ETH"),
                        bytes.concat(type(LSSVMPairERC721ETH).creationCode, abi.encode(royaltyRegistry))
                    )
                )
            );
            LSSVMPairERC721ERC20 erc721ERC20Template = LSSVMPairERC721ERC20(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMPairERC721ERC20"),
                    bytes.concat(type(LSSVMPairERC721ERC20).creationCode, abi.encode(royaltyRegistry))
                )
            );
            LSSVMPairERC1155ETH erc1155ETHTemplate = LSSVMPairERC1155ETH(
                payable(
                    create3.deploy(
                        getCreate3ContractSalt("LSSVMPairERC1155ETH"),
                        bytes.concat(type(LSSVMPairERC1155ETH).creationCode, abi.encode(royaltyRegistry))
                    )
                )
            );
            LSSVMPairERC1155ERC20 erc1155ERC20Template = LSSVMPairERC1155ERC20(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMPairERC1155ERC20"),
                    bytes.concat(type(LSSVMPairERC1155ERC20).creationCode, abi.encode(royaltyRegistry))
                )
            );
            address deployer = vm.addr(deployerPrivateKey);
            factoryConstructorArgs = abi.encode(
                erc721ETHTemplate,
                erc721ERC20Template,
                erc1155ETHTemplate,
                erc1155ERC20Template,
                protocolFeeRecipient,
                protocolFee,
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
        linearCurve = LinearCurve(create3.deploy(getCreate3ContractSalt("LinearCurve"), type(LinearCurve).creationCode));
        exponentialCurve = ExponentialCurve(
            create3.deploy(getCreate3ContractSalt("ExponentialCurve"), type(ExponentialCurve).creationCode)
        );
        xykCurve = XykCurve(create3.deploy(getCreate3ContractSalt("XykCurve"), type(XykCurve).creationCode));

        // whitelist bonding curves
        factory.setBondingCurveAllowed(linearCurve, true);
        factory.setBondingCurveAllowed(exponentialCurve, true);
        factory.setBondingCurveAllowed(xykCurve, true);

        // deploy routers
        router = LSSVMRouter(
            payable(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMRouter"),
                    bytes.concat(type(LSSVMRouter).creationCode, abi.encode(factory))
                )
            )
        );

        // whitelist routers
        factory.setRouterAllowed(router, true);

        // transfer factory ownership
        {
            address owner = vm.envAddress("OWNER");
            factory.transferOwnership(owner);
        }

        vm.stopBroadcast();
    }
}
