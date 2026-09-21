// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BadgeNFT} from "../src/BadgeNFT.sol";

contract BadgeNFTTest is Test {
    BadgeNFT badge;
    address admin = address(0xA11CE);
    address minter = address(0xB0B);
    address user = address(0xCAFE);

    function setUp() public {
        badge = new BadgeNFT(admin, minter);
    }

    function test_MinterCanMint() public {
        vm.prank(minter);
        uint256 tokenId = badge.mint(user, "first-prediction");

        assertEq(badge.ownerOf(tokenId), user);
        assertEq(badge.badgeSlugOf(tokenId), "first-prediction");
    }

    function test_RevertWhen_NonMinterMints() public {
        vm.prank(user);
        vm.expectRevert();
        badge.mint(user, "first-prediction");
    }

    function test_RevertWhen_BadgeIsTransferred() public {
        vm.prank(minter);
        uint256 tokenId = badge.mint(user, "first-prediction");

        vm.prank(user);
        vm.expectRevert(BadgeNFT.SoulboundTransferBlocked.selector);
        badge.transferFrom(user, admin, tokenId);
    }

    function test_AdminCanRotateMinter() public {
        address newMinter = address(0xD00D);
        bytes32 minterRole = badge.MINTER_ROLE();

        vm.prank(admin);
        badge.grantRole(minterRole, newMinter);

        vm.prank(newMinter);
        uint256 tokenId = badge.mint(user, "second-badge");
        assertEq(badge.ownerOf(tokenId), user);
    }

    function test_RevertWhen_NonAdminRotatesMinter() public {
        bytes32 minterRole = badge.MINTER_ROLE();

        vm.prank(user);
        vm.expectRevert();
        badge.grantRole(minterRole, user);
    }
}
