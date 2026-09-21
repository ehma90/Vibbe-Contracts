// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Vibbe Fan token. A standard, freely transferable ERC-20. Only the
/// backend signer (MINTER_ROLE) can mint — used for faucet drips and pool
/// payouts, both decided off-chain and pushed on-chain by the backend.
contract VBFToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @param admin Can grant/revoke MINTER_ROLE (e.g. to rotate signers).
    /// @param minter The backend signer address that will call mint().
    constructor(address admin, address minter) ERC20("Vibbe Fan Token", "VBF") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}
