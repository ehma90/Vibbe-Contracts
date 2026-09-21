// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VBFToken} from "../src/VBFToken.sol";

contract VBFTokenTest is Test {
    VBFToken vbf;
    address admin = address(0xA11CE);
    address minter = address(0xB0B);
    address user = address(0xCAFE);

    function setUp() public {
        vbf = new VBFToken(admin, minter);
    }

    function test_MinterCanMint() public {
        vm.prank(minter);
        vbf.mint(user, 1_000e18);

        assertEq(vbf.balanceOf(user), 1_000e18);
    }

    function test_RevertWhen_NonMinterMints() public {
        vm.prank(user);
        vm.expectRevert();
        vbf.mint(user, 1_000e18);
    }

    function test_UserCanTransferReceivedTokens() public {
        vm.prank(minter);
        vbf.mint(user, 500e18);

        vm.prank(user);
        vbf.transfer(admin, 200e18);

        assertEq(vbf.balanceOf(user), 300e18);
        assertEq(vbf.balanceOf(admin), 200e18);
    }

    function test_AdminCanRotateMinter() public {
        address newMinter = address(0xD00D);
        bytes32 minterRole = vbf.MINTER_ROLE();

        vm.prank(admin);
        vbf.grantRole(minterRole, newMinter);

        vm.prank(newMinter);
        vbf.mint(user, 100e18);
        assertEq(vbf.balanceOf(user), 100e18);
    }
}
