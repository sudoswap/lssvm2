// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CREATE3Factory} from "create3-factory/CREATE3Factory.sol";

import "forge-std/Script.sol";

import {LSSVMPair} from "../src/LSSVMPair.sol";
import {LSSVMRouter} from "../src/LSSVMRouter.sol";
import {LSSVMRouter2} from "../src/LSSVMRouter2.sol";
import {LSSVMPairETH} from "../src/LSSVMPairETH.sol";
import {LSSVMPairERC20} from "../src/LSSVMPairERC20.sol";
import {XykCurve} from "../src/bonding-curves/XykCurve.sol";
import {LSSVMPairFactory} from "../src/LSSVMPairFactory.sol";
import {LinearCurve} from "../src/bonding-curves/LinearCurve.sol";
import {ExponentialCurve} from "../src/bonding-curves/ExponentialCurve.sol";
import {LSSVMRouterWithRoyalties} from "../src/LSSVMRouterWithRoyalties.sol";

contract DeployScript is Script {
    function run()
        external
        returns (
            LSSVMPairFactory factory,
            LSSVMRouter router,
            LSSVMRouter2 router2,
            LSSVMRouterWithRoyalties routerWithRoyalties,
            LinearCurve linearCurve,
            ExponentialCurve exponentialCurve,
            XykCurve xykCurve
        )
    {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        CREATE3Factory create3 = CREATE3Factory(
            0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf
        );

        uint256 protocolFee = vm.envUint("PROTOCOL_FEE");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");

        vm.startBroadcast(deployerPrivateKey);

        // deploy factory
        {
            LSSVMPairETH ethTemplate = LSSVMPairETH(
                payable(
                    create3.deploy(
                        keccak256("LSSVMPairETH"),
                        type(LSSVMPairETH).creationCode
                    )
                )
            );
            LSSVMPairERC20 erc20Template = LSSVMPairERC20(
                create3.deploy(
                    keccak256("LSSVMPairERC20"),
                    type(LSSVMPairERC20).creationCode
                )
            );
            address deployer = vm.addr(deployerPrivateKey);
            factory = LSSVMPairFactory(
                payable(
                    create3.deploy(
                        keccak256("LSSVMPairFactory"),
                        bytes.concat(
                            type(LSSVMPairFactory).creationCode,
                            abi.encode(
                                ethTemplate,
                                erc20Template,
                                protocolFeeRecipient,
                                protocolFee,
                                deployer
                            )
                        )
                    )
                )
            );
        }

        // deploy bonding curves
        linearCurve = LinearCurve(
            create3.deploy(
                keccak256("LinearCurve"),
                type(LinearCurve).creationCode
            )
        );
        exponentialCurve = ExponentialCurve(
            create3.deploy(
                keccak256("ExponentialCurve"),
                type(ExponentialCurve).creationCode
            )
        );
        xykCurve = XykCurve(
            create3.deploy(keccak256("XykCurve"), type(XykCurve).creationCode)
        );

        // whitelist bonding curves
        factory.setBondingCurveAllowed(linearCurve, true);
        factory.setBondingCurveAllowed(exponentialCurve, true);
        factory.setBondingCurveAllowed(xykCurve, true);

        // deploy routers
        router = LSSVMRouter(
            payable(
                create3.deploy(
                    keccak256("LSSVMRouter"),
                    bytes.concat(
                        type(LSSVMRouter).creationCode,
                        abi.encode(factory)
                    )
                )
            )
        );
        router2 = LSSVMRouter2(
            payable(
                create3.deploy(
                    keccak256("LSSVMRouter2"),
                    bytes.concat(
                        type(LSSVMRouter2).creationCode,
                        abi.encode(factory)
                    )
                )
            )
        );
        routerWithRoyalties = LSSVMRouterWithRoyalties(
            payable(
                create3.deploy(
                    keccak256("LSSVMRouterWithRoyalties"),
                    bytes.concat(
                        type(LSSVMRouterWithRoyalties).creationCode,
                        abi.encode(factory)
                    )
                )
            )
        );

        // whitelist routers
        factory.setRouterAllowed(router, true);
        factory.setRouterAllowed(LSSVMRouter(payable(address(router2))), true);
        factory.setRouterAllowed(routerWithRoyalties, true);

        // transfer factory ownership
        {
            address owner = vm.envAddress("OWNER");
            factory.transferOwnership(owner);
        }

        vm.stopBroadcast();
    }
}
