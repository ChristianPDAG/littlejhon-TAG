// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IProofOfReserve} from "../interfaces/IProofOfReserve.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {SafetyChecks} from "../libraries/SafetyChecks.sol";

/// @title ProofOfReserve — Automated reserve verification via Chainlink PoR feeds
/// @notice Ensures every tokenized RWA is backed 1:1 by real-world assets
contract ProofOfReserve is IProofOfReserve, Ownable {
    // ─── Constants ──────────────────────────────────────────────────
    uint256 private constant SAFE_POR_INTERVAL = 1 hours;

    // ─── Storage ────────────────────────────────────────────────────
    struct FeedConfig {
        AggregatorV3Interface feed;
        uint256 maxStaleness;
        bool registered;
    }

    mapping(address => FeedConfig) private _feeds;

    // ─── Constructor ────────────────────────────────────────────────
    constructor(address initialOwner) Ownable(initialOwner) {}

    // ─── External Functions ─────────────────────────────────────────

    /// @inheritdoc IProofOfReserve
    function registerFeed(address token, address feed, uint256 maxStaleness) external onlyOwner {
        SafetyChecks.requireNonZero(token);
        SafetyChecks.requireNonZero(feed);
        require(maxStaleness > 0, "ProofOfReserve: zero staleness");

        _feeds[token] = FeedConfig({feed: AggregatorV3Interface(feed), maxStaleness: maxStaleness, registered: true});

        emit FeedRegistered(token, feed);
    }

    /// @inheritdoc IProofOfReserve
    function removeFeed(address token) external onlyOwner {
        if (!_feeds[token].registered) revert FeedNotRegistered(token);
        delete _feeds[token];
        emit FeedRemoved(token);
    }

    /// @inheritdoc IProofOfReserve
    function verifyReserve(address token) external view returns (bool) {
        (uint256 reserves, uint256 totalSupply) = _readReserve(token);
        return reserves >= totalSupply;
    }

    /// @inheritdoc IProofOfReserve
    function getReserveRatio(address token) external view returns (uint256 ratio) {
        (uint256 reserves, uint256 totalSupply) = _readReserve(token);
        if (totalSupply == 0) return type(uint256).max; // No supply → infinite ratio
        return (reserves * 1e18) / totalSupply;
    }

    // ─── Internal Helpers ───────────────────────────────────────────

    /// @dev Reads validated reserve data: rejects future timestamps, stale rounds, and negative balances.
    function _readReserve(address token) internal view returns (uint256 reserves, uint256 totalSupply) {
        FeedConfig memory config = _feeds[token];
        if (!config.registered) revert FeedNotRegistered(token);

        (, int256 reserveBalance,, uint256 updatedAt,) = config.feed.latestRoundData();

        // updatedAt in the future signals a misbehaving feed — treat as stale.
        if (updatedAt == 0 || updatedAt > block.timestamp) revert StaleData(token, 0);

        uint256 age = block.timestamp - updatedAt;
        if (age > config.maxStaleness) revert StaleData(token, age);

        // A negative reserve balance is nonsensical; without this guard the int256→uint256 cast
        // would wrap to ~2^256 and silently pass the >= totalSupply check.
        if (reserveBalance < 0) revert ReserveUndercollateralized(token, 0);

        reserves = uint256(reserveBalance);
        totalSupply = IERC20(token).totalSupply();
    }
}