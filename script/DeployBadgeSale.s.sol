// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {BadgeSale} from "../src/BadgeSale.sol";

/// @notice Deploys BadgeSale against an existing BadgeNFT. DEFAULT_ADMIN_ROLE goes to
/// CONTRACT_ADMIN_ADDRESS, VOUCHER_SIGNER_ROLE to BACKEND_MINTER_ADDRESS (the backend signer),
/// and payments go to TREASURY_ADDRESS.
///
/// One more step afterwards, sent by the BadgeNFT admin: BadgeNFT.grantRole(MINTER_ROLE, <BadgeSale>).
/// Until then every paid mint reverts (and takes no payment).
contract DeployBadgeSale is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("CONTRACT_ADMIN_ADDRESS");
        address voucherSigner = vm.envAddress("BACKEND_MINTER_ADDRESS");
        address badgeNft = vm.envAddress("BADGE_NFT_ADDRESS");
        address payable treasury = payable(vm.envAddress("TREASURY_ADDRESS"));

        vm.startBroadcast(deployerPrivateKey);
        BadgeSale sale = new BadgeSale(admin, voucherSigner, badgeNft, treasury);
        vm.stopBroadcast();

        console.log("BadgeSale deployed to:", address(sale));
        console.log("Next, from the BadgeNFT admin: grantRole(MINTER_ROLE, BadgeSale) on", badgeNft);
    }
}
