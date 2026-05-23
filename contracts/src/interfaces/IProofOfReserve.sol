// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IProofOfReserve — Automated reserve attestation for RWA backing
/// @notice Verifies that tokenized assets are backed 1:1 by real-world reserves
interface IProofOfReserve {
    /// @dev Emitted when reserve status changes
    event ReserveVerified(address indexed token, uint256 onChainAmount, uint256 reportedReserves);
    event ReserveFailed(address indexed token, uint256 deficit);
    event FeedRegistered(address indexed token, address feed);
    event FeedRemoved(address indexed token);

    /// @dev Custom errors
    error ReserveUndercollateralized(address token, uint256 deficit);
    error FeedNotRegistered(address token);
    error StaleData(address token, uint256 age);

    /// @notice Register a Chainlink PoR feed for a token
    /// @param token The RWA token address
    /// @param feed The Chainlink Proof of Reserve feed address
    /// @param maxStaleness Maximum acceptable data age in seconds
    function registerFeed(address token, address feed, uint256 maxStaleness) external;

    /// @notice Remove a registered feed
    function removeFeed(address token) external;

    /// @notice Verify that reserves back the full on-chain supply
    /// @param token The RWA token to verify
    /// @return isBacked True if reserves >= total supply
    function verifyReserve(address token) external view returns (bool);

    /// @notice Get the current reserve ratio for a token
    /// @return ratio The reserve ratio scaled by 1e18 (1e18 = 100%)
    function getReserveRatio(address token) external view returns (uint256 ratio);
}