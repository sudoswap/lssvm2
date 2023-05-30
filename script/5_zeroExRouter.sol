// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CREATE3Script} from "./base/CREATE3Script.sol";
import {ZeroExRouter} from "../src/ZeroExRouter.sol";

contract PropertyCheckingDeploy is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() external returns (
            ZeroExRouter router
        ) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        router = ZeroExRouter(
            payable(create3.deploy(
                getCreate3ContractSalt("ZeroExRouter"), bytes.concat(type(ZeroExRouter).creationCode)
            )
        ));
        vm.stopBroadcast();
    }
}