// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IBadgeNFT {
    function mint(address to, string calldata badgeSlug) external returns (uint256 tokenId);
}

/// @notice Paid minting for Vibbe badges. A player who has unlocked a badge in the app mints it
/// themselves and pays the mint price in HYPE (HyperEVM's native token) in the same transaction.
///
/// The app still decides who has unlocked what: the backend signs a short-lived voucher
/// (wallet, badge, price, deadline) and this contract only mints against a valid one. So a badge
/// can't be bought without being earned, and the price (about $1 of HYPE, worked out by the backend
/// when it signs) can't be changed by the player.
///
/// This contract needs MINTER_ROLE on BadgeNFT. It never holds funds: each payment goes straight
/// to the treasury inside the mint transaction.
contract BadgeSale is AccessControl, EIP712 {
    bytes32 public constant VOUCHER_SIGNER_ROLE = keccak256("VOUCHER_SIGNER_ROLE");
    bytes32 private constant VOUCHER_TYPEHASH =
        keccak256("MintVoucher(address wallet,string badgeSlug,uint256 price,uint256 deadline)");

    IBadgeNFT public immutable badge;
    address payable public treasury;

    /// @dev wallet => keccak256(badgeSlug) => BadgeNFT token ID minted through this contract (0 = none).
    /// Lets the backend see a paid mint even if the app never heard back from the player's browser.
    mapping(address wallet => mapping(bytes32 slugHash => uint256 tokenId)) private _mintedTokenId;

    event BadgePurchased(address indexed wallet, uint256 indexed tokenId, string badgeSlug, uint256 price);
    event TreasuryChanged(address indexed previousTreasury, address indexed newTreasury);

    error ZeroAddress();
    error VoucherExpired();
    error InvalidVoucher();
    error WrongPayment(uint256 sent, uint256 price);
    error AlreadyMinted();
    error TreasuryPaymentFailed();

    /// @param admin Can change the treasury and grant/revoke VOUCHER_SIGNER_ROLE.
    /// @param voucherSigner The backend signer whose vouchers are accepted.
    /// @param badgeNft The deployed BadgeNFT this contract mints on.
    /// @param treasury_ Receives every mint payment.
    constructor(address admin, address voucherSigner, address badgeNft, address payable treasury_)
        EIP712("VibbeBadgeSale", "1")
    {
        if (admin == address(0) || voucherSigner == address(0) || badgeNft == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VOUCHER_SIGNER_ROLE, voucherSigner);
        badge = IBadgeNFT(badgeNft);
        treasury = treasury_;
    }

    /// @notice Mints `badgeSlug` to the caller for exactly `price` wei of HYPE.
    /// @param signature The backend's signature over (caller, badgeSlug, price, deadline).
    function mint(string calldata badgeSlug, uint256 price, uint256 deadline, bytes calldata signature)
        external
        payable
        returns (uint256 tokenId)
    {
        if (block.timestamp > deadline) revert VoucherExpired();
        if (msg.value != price) revert WrongPayment(msg.value, price);

        bytes32 slugHash = keccak256(bytes(badgeSlug));
        if (_mintedTokenId[msg.sender][slugHash] != 0) revert AlreadyMinted();

        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(VOUCHER_TYPEHASH, msg.sender, slugHash, price, deadline)));
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || !hasRole(VOUCHER_SIGNER_ROLE, signer)) revert InvalidVoucher();

        // Claim the slot before any external call; a re-entrant mint for the same badge then fails
        // with AlreadyMinted. Token IDs start at 1, so the placeholder is never a real ID.
        _mintedTokenId[msg.sender][slugHash] = type(uint256).max;
        tokenId = badge.mint(msg.sender, badgeSlug);
        _mintedTokenId[msg.sender][slugHash] = tokenId;

        emit BadgePurchased(msg.sender, tokenId, badgeSlug, price);

        (bool paid,) = treasury.call{value: msg.value}("");
        if (!paid) revert TreasuryPaymentFailed();
    }

    /// @notice The BadgeNFT token ID `wallet` minted for `badgeSlug` through this contract, or 0.
    function mintedTokenId(address wallet, string calldata badgeSlug) external view returns (uint256) {
        return _mintedTokenId[wallet][keccak256(bytes(badgeSlug))];
    }

    function setTreasury(address payable newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryChanged(treasury, newTreasury);
        treasury = newTreasury;
    }
}
