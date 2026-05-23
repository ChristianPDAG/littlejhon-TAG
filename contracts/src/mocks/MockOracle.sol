// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title MockOracle — Chainlink-compatible mock for testing
/// @notice Simulates Chainlink price feeds and Proof of Reserve feeds on testnet
contract MockOracle is AggregatorV3Interface {
    // ─── Storage ────────────────────────────────────────────────────
    uint8 private _decimals;
    string private _description;
    uint256 private _version;
    uint80 private _currentRoundId;

    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    mapping(uint80 => RoundData) private _rounds;

    // ─── Constructor ────────────────────────────────────────────────
    constructor(uint8 decimals_, string memory description_) {
        _decimals = decimals_;
        _description = description_;
        _version = 1;
    }

    // ─── Admin Functions ────────────────────────────────────────────

    /// @notice Set the price for the current round (test only)
    function setPrice(int256 price) external {
        _currentRoundId++;
        _rounds[_currentRoundId] = RoundData({
            answer: price,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: _currentRoundId
        });
    }

    /// @notice Set a round with custom timestamp (for staleness testing)
    function setRound(int256 price, uint256 updatedAt) external {
        _currentRoundId++;
        _rounds[_currentRoundId] = RoundData({
            answer: price,
            startedAt: updatedAt,
            updatedAt: updatedAt,
            answeredInRound: _currentRoundId
        });
    }

    // ─── AggregatorV3Interface Implementation ───────────────────────

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function version() external view returns (uint256) {
        return _version;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory rd = _rounds[_currentRoundId];
        return (_currentRoundId, rd.answer, rd.startedAt, rd.updatedAt, rd.answeredInRound);
    }
}