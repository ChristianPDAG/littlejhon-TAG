// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IComplianceRegistry — ERC-3643 inspired identity & compliance interface
/// @notice Manages KYC/AML verification status for RWA token holders
interface IComplianceRegistry {
    /// @dev Emitted when an identity is verified or revoked
    event IdentityVerified(address indexed user, uint256 jurisdiction, uint256 expiry);
    event IdentityRevoked(address indexed user);
    event JurisdictionBlocked(uint256 jurisdiction);
    event JurisdictionUnblocked(uint256 jurisdiction);

    /// @dev Custom errors for gas-efficient revert reasons
    error IdentityNotVerified(address user);
    error IdentityExpired(address user);
    error JurisdictionIsBlocked(uint256 jurisdiction);

    /// @notice Verify a user's identity with jurisdiction and expiry
    /// @param user Address of the user to verify
    /// @param jurisdiction Numeric code for regulatory region (e.g., 1=US, 2=EU/MiCA)
    /// @param expiry Timestamp when verification expires
    function verifyIdentity(address user, uint256 jurisdiction, uint256 expiry) external;

    /// @notice Revoke a user's verified status
    function revokeIdentity(address user) external;

    /// @notice Check if a user is currently verified and not expired
    /// @return isVerified Whether the user passes compliance checks
    function isVerified(address user) external view returns (bool);

    /// @notice Get the full identity record for a user
    /// @return jurisdiction The regulatory jurisdiction code
    /// @return expiry The expiration timestamp
    /// @return active Whether the identity is currently active
    function getIdentity(address user) external view returns (uint256 jurisdiction, uint256 expiry, bool active);

    /// @notice Block all transfers from a specific jurisdiction
    function blockJurisdiction(uint256 jurisdiction) external;

    /// @notice Unblock a previously blocked jurisdiction
    function unblockJurisdiction(uint256 jurisdiction) external;

    /// @notice Check if a jurisdiction is blocked
    function isJurisdictionBlocked(uint256 jurisdiction) external view returns (bool);
}