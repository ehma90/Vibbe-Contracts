// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Achievement badges for Vibbe users. Soulbound: mintable by the
/// backend signer, non-transferable once minted (so a badge always reflects
/// something the holder actually did, not something they bought).
contract BadgeNFT is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private _nextTokenId = 1;
    mapping(uint256 tokenId => string badgeSlug) private _badgeSlugs;

    event BadgeMinted(address indexed to, uint256 indexed tokenId, string badgeSlug);

    error SoulboundTransferBlocked();

    /// @param admin Can grant/revoke MINTER_ROLE (e.g. to rotate signers). Should be a
    /// separate, more carefully guarded address than the day-to-day minter.
    /// @param minter The backend signer address that will call mint().n01kows
    
    constructor(address admin, address minter) ERC721("Vibbe Badge", "VBADGE") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(address to, string calldata badgeSlug) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _badgeSlugs[tokenId] = badgeSlug;
        _safeMint(to, tokenId);
        emit BadgeMinted(to, tokenId, badgeSlug);
    }

    function badgeSlugOf(uint256 tokenId) external view returns (string memory) {
        _requireOwned(tokenId);
        return _badgeSlugs[tokenId];
    }

    /// @dev Blocks transfers/approvals-based moves while still allowing the initial mint
    /// (from == address(0)). Any transfer attempt after that reverts.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0)) {
            revert SoulboundTransferBlocked();
        }
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
