// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IComplianceRegistry} from "../interfaces/IComplianceRegistry.sol";
import {SafetyChecks} from "../libraries/SafetyChecks.sol";

/// @title ComplianceRegistry — ERC-3643 inspired on-chain identity & compliance
/// @notice Tracks KYC/AML status and jurisdiction blocking for RWA transfers
contract ComplianceRegistry is IComplianceRegistry, Ownable {
    // ─── Storage ────────────────────────────────────────────────────
    struct Identity {
        uint256 jurisdiction;
        uint256 expiry;
        bool active;
    }

    mapping(address => Identity) private _identities;
    mapping(uint256 => bool) private _blockedJurisdictions;

    // ─── Constructor ────────────────────────────────────────────────
    constructor(address initialOwner) Ownable(initialOwner) {}

    // ─── External Functions ─────────────────────────────────────────

    /// @inheritdoc IComplianceRegistry
    function verifyIdentity(address user, uint256 jurisdiction, uint256 expiry)
        external
        onlyOwner
    {
        SafetyChecks.requireNonZero(user);
        SafetyChecks.requireValidExpiry(expiry);

        _identities[user] = Identity({jurisdiction: jurisdiction, expiry: expiry, active: true});

        emit IdentityVerified(user, jurisdiction, expiry);
    }

    /// @inheritdoc IComplianceRegistry
    function revokeIdentity(address user) external onlyOwner {
        SafetyChecks.requireNonZero(user);
        _identities[user].active = false;
        emit IdentityRevoked(user);
    }

    /// @inheritdoc IComplianceRegistry
    function isVerified(address user) external view returns (bool) {
        Identity memory id = _identities[user];
        return id.active && id.expiry > block.timestamp && !_blockedJurisdictions[id.jurisdiction];
    }

    /// @inheritdoc IComplianceRegistry
    function getIdentity(address user) external view returns (uint256 jurisdiction, uint256 expiry, bool active) {
        Identity memory id = _identities[user];
        return (id.jurisdiction, id.expiry, id.active);
    }

    /// @inheritdoc IComplianceRegistry
    function blockJurisdiction(uint256 jurisdiction) external onlyOwner {
        _blockedJurisdictions[jurisdiction] = true;
        emit JurisdictionBlocked(jurisdiction);
    }

    /// @inheritdoc IComplianceRegistry
    function unblockJurisdiction(uint256 jurisdiction) external onlyOwner {
        _blockedJurisdictions[jurisdiction] = false;
        emit JurisdictionUnblocked(jurisdiction);
    }

    /// @inheritdoc IComplianceRegistry
    function isJurisdictionBlocked(uint256 jurisdiction) external view returns (bool) {
        return _blockedJurisdictions[jurisdiction];
    }
}