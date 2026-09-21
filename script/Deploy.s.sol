// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {BadgeNFT} from "../src/BadgeNFT.sol";
import {VBFToken} from "../src/VBFToken.sol";

/// @notice Deploys BadgeNFT + VBFToken, granting DEFAULT_ADMIN_ROLE to
/// CONTRACT_ADMIN_ADDRESS and MINTER_ROLE to BACKEND_MINTER_ADDRESS on both.
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("CONTRACT_ADMIN_ADDRESS");
        address minter = vm.envAddress("BACKEND_MINTER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        BadgeNFT badge = new BadgeNFT(admin, minter);
        VBFToken vbf = new VBFToken(admin, minter);

        vm.stopBroadcast();

        console.log("BadgeNFT deployed to:", address(badge));
        console.log("VBFToken deployed to:", address(vbf));
    }
}
