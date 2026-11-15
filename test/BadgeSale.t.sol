// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BadgeNFT} from "../src/BadgeNFT.sol";
import {BadgeSale} from "../src/BadgeSale.sol";

/// A wallet contract that tries to mint the same badge again while receiving it.
contract ReentrantBuyer {
    BadgeSale sale;
    string slug;
    uint256 price;
    uint256 deadline;
    bytes sig;
    bool public reentryFailed;

    function buy(BadgeSale sale_, string calldata slug_, uint256 price_, uint256 deadline_, bytes calldata sig_)
        external
        payable
    {
        sale = sale_;
        slug = slug_;
        price = price_;
        deadline = deadline_;
        sig = sig_;
        sale.mint{value: price_}(slug_, price_, deadline_, sig_);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        try sale.mint{value: price}(slug, price, deadline, sig) {}
        catch {
            reentryFailed = true;
        }
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

contract RejectsPayment {
    receive() external payable {
        revert("no");
    }
}

contract BadgeSaleTest is Test {
    BadgeNFT badge;
    BadgeSale sale;

    address admin = address(0xA11CE);
    address backendMinter = address(0xB0B);
    address payable treasury = payable(address(0x7EA5));
    uint256 signerKey = 0x51617;
    address signer;
    address user = address(0xCAFE);
    address other = address(0xD00D);

    uint256 constant PRICE = 0.015 ether;
    string constant SLUG = "rising-predictor";

    bytes32 constant VOUCHER_TYPEHASH =
        keccak256("MintVoucher(address wallet,string badgeSlug,uint256 price,uint256 deadline)");

    function setUp() public {
        signer = vm.addr(signerKey);
        badge = new BadgeNFT(admin, backendMinter);
        sale = new BadgeSale(admin, signer, address(badge), treasury);
        bytes32 minterRole = badge.MINTER_ROLE();
        vm.prank(admin);
        badge.grantRole(minterRole, address(sale));
        vm.deal(user, 1 ether);
        vm.deal(other, 1 ether);
        vm.warp(1_800_000_000);
    }

    function _sign(uint256 key, address saleAddr, address wallet, string memory slug, uint256 price, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("VibbeBadgeSale"),
                keccak256("1"),
                block.chainid,
                saleAddr
            )
        );
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, wallet, keccak256(bytes(slug)), price, deadline));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, keccak256(abi.encodePacked("\x19\x01", domain, structHash)));
        return abi.encodePacked(r, s, v);
    }

    function _voucher(address wallet, string memory slug, uint256 price, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        return _sign(signerKey, address(sale), wallet, slug, price, deadline);
    }

    function test_PaidMintGivesBadgeAndPaysTreasury() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);

        vm.expectEmit(true, true, false, true);
        emit BadgeSale.BadgePurchased(user, 1, SLUG, PRICE);
        vm.prank(user);
        uint256 tokenId = sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);

        assertEq(tokenId, 1);
        assertEq(badge.ownerOf(tokenId), user);
        assertEq(badge.badgeSlugOf(tokenId), SLUG);
        assertEq(sale.mintedTokenId(user, SLUG), tokenId);
        assertEq(treasury.balance, PRICE);
        assertEq(address(sale).balance, 0);
        assertEq(user.balance, 1 ether - PRICE);
    }

    function test_RevertWhen_PaymentTooLow() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(BadgeSale.WrongPayment.selector, PRICE - 1, PRICE));
        sale.mint{value: PRICE - 1}(SLUG, PRICE, deadline, sig);
    }

    function test_RevertWhen_PaymentTooHigh() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(BadgeSale.WrongPayment.selector, PRICE + 1, PRICE));
        sale.mint{value: PRICE + 1}(SLUG, PRICE, deadline, sig);
    }

    function test_RevertWhen_PlayerLowersThePrice() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.prank(user);
        vm.expectRevert(BadgeSale.InvalidVoucher.selector);
        sale.mint{value: 1}(SLUG, 1, deadline, sig);
    }

    function test_RevertWhen_VoucherExpired() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.warp(deadline + 1);
        vm.prank(user);
        vm.expectRevert(BadgeSale.VoucherExpired.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);
    }

    function test_RevertWhen_PlayerExtendsTheDeadline() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.warp(deadline + 1);
        vm.prank(user);
        vm.expectRevert(BadgeSale.InvalidVoucher.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline + 1000, sig);
    }

    function test_RevertWhen_SomeoneElseUsesTheVoucher() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.prank(other);
        vm.expectRevert(BadgeSale.InvalidVoucher.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);
    }

    function test_RevertWhen_VoucherIsForAnotherBadge() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.prank(user);
        vm.expectRevert(BadgeSale.InvalidVoucher.selector);
        sale.mint{value: PRICE}("legend", PRICE, deadline, sig);
    }

    function test_RevertWhen_SignedByAStranger() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _sign(0xBAD, address(sale), user, SLUG, PRICE, deadline);
        vm.prank(user);
        vm.expectRevert(BadgeSale.InvalidVoucher.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);
    }

    function test_RevertWhen_SignatureIsGarbage() public {
        vm.prank(user);
        vm.expectRevert(BadgeSale.InvalidVoucher.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, block.timestamp + 600, hex"1234");
    }

    function test_RevertWhen_VoucherWasSignedForAnotherSaleContract() public {
        BadgeSale otherSale = new BadgeSale(admin, signer, address(badge), treasury);
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _sign(signerKey, address(otherSale), user, SLUG, PRICE, deadline);
        vm.prank(user);
        vm.expectRevert(BadgeSale.InvalidVoucher.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);
    }

    function test_RevertWhen_SameBadgeMintedTwice() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.prank(user);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);

        // Replaying the same voucher, and using a fresh one, both fail.
        vm.prank(user);
        vm.expectRevert(BadgeSale.AlreadyMinted.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);

        bytes memory fresh = _voucher(user, SLUG, PRICE, deadline + 1);
        vm.prank(user);
        vm.expectRevert(BadgeSale.AlreadyMinted.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline + 1, fresh);
        assertEq(treasury.balance, PRICE);
    }

    function test_DifferentBadgesAndDifferentPlayersMintSeparately() public {
        uint256 deadline = block.timestamp + 600;
        vm.prank(user);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, _voucher(user, SLUG, PRICE, deadline));
        vm.prank(user);
        sale.mint{value: PRICE}("legend", PRICE, deadline, _voucher(user, "legend", PRICE, deadline));
        vm.prank(other);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, _voucher(other, SLUG, PRICE, deadline));
        assertEq(treasury.balance, 3 * PRICE);
        assertEq(sale.mintedTokenId(other, SLUG), 3);
        assertEq(sale.mintedTokenId(other, "legend"), 0);
    }

    function test_ReentrantMintOfTheSameBadgeFails() public {
        ReentrantBuyer buyer = new ReentrantBuyer();
        vm.deal(address(buyer), 1 ether);
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(address(buyer), SLUG, PRICE, deadline);
        buyer.buy(sale, SLUG, PRICE, deadline, sig);
        assertTrue(buyer.reentryFailed());
        assertEq(treasury.balance, PRICE);
        assertEq(sale.mintedTokenId(address(buyer), SLUG), 1);
    }

    function test_RevokedSignerIsRefused() public {
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        bytes32 role = sale.VOUCHER_SIGNER_ROLE();
        vm.prank(admin);
        sale.revokeRole(role, signer);
        vm.prank(user);
        vm.expectRevert(BadgeSale.InvalidVoucher.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);
    }

    function test_RevertWhen_SaleHasNoMinterRole() public {
        BadgeSale unwired = new BadgeSale(admin, signer, address(badge), treasury);
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _sign(signerKey, address(unwired), user, SLUG, PRICE, deadline);
        vm.prank(user);
        vm.expectRevert();
        unwired.mint{value: PRICE}(SLUG, PRICE, deadline, sig);
        assertEq(user.balance, 1 ether);
    }

    function test_FailedTreasuryPaymentUndoesTheMint() public {
        RejectsPayment bad = new RejectsPayment();
        vm.prank(admin);
        sale.setTreasury(payable(address(bad)));
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, PRICE, deadline);
        vm.prank(user);
        vm.expectRevert(BadgeSale.TreasuryPaymentFailed.selector);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, sig);
        assertEq(sale.mintedTokenId(user, SLUG), 0);
        assertEq(user.balance, 1 ether);
    }

    function test_AdminCanChangeTreasuryAndOthersCannot() public {
        address payable next = payable(address(0x7EA6));
        vm.prank(user);
        vm.expectRevert();
        sale.setTreasury(next);

        vm.prank(admin);
        sale.setTreasury(next);
        uint256 deadline = block.timestamp + 600;
        vm.prank(user);
        sale.mint{value: PRICE}(SLUG, PRICE, deadline, _voucher(user, SLUG, PRICE, deadline));
        assertEq(next.balance, PRICE);
        assertEq(treasury.balance, 0);

        vm.prank(admin);
        vm.expectRevert(BadgeSale.ZeroAddress.selector);
        sale.setTreasury(payable(address(0)));
    }

    function test_FreeVoucherMintsForNothing() public {
        uint256 deadline = block.timestamp + 600;
        vm.prank(user);
        sale.mint(SLUG, 0, deadline, _voucher(user, SLUG, 0, deadline));
        assertEq(badge.ownerOf(1), user);
    }

    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert(BadgeSale.ZeroAddress.selector);
        new BadgeSale(address(0), signer, address(badge), treasury);
        vm.expectRevert(BadgeSale.ZeroAddress.selector);
        new BadgeSale(admin, address(0), address(badge), treasury);
        vm.expectRevert(BadgeSale.ZeroAddress.selector);
        new BadgeSale(admin, signer, address(0), treasury);
        vm.expectRevert(BadgeSale.ZeroAddress.selector);
        new BadgeSale(admin, signer, address(badge), payable(address(0)));
    }

    function testFuzz_OnlyTheExactPriceIsAccepted(uint96 price, uint96 sent) public {
        vm.assume(price != sent);
        vm.deal(user, type(uint96).max);
        uint256 deadline = block.timestamp + 600;
        bytes memory sig = _voucher(user, SLUG, price, deadline);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(BadgeSale.WrongPayment.selector, uint256(sent), uint256(price)));
        sale.mint{value: sent}(SLUG, price, deadline, sig);
    }
}
