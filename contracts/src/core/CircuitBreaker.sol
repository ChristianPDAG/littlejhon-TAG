// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICircuitBreaker} from "../interfaces/ICircuitBreaker.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {SafetyChecks} from "../libraries/SafetyChecks.sol";

/// @title CircuitBreaker — Automatic emergency halt on price anomalies
/// @notice Monitors Chainlink price feeds and triggers pauses when deviations exceed thresholds
contract CircuitBreaker is ICircuitBreaker, Ownable {
    // ─── Constants ──────────────────────────────────────────────────
    uint256 private constant DEFAULT_THRESHOLD_BPS = 1500; // 15%

    // ─── Storage ────────────────────────────────────────────────────
    struct TokenConfig {
        AggregatorV3Interface priceFeed;
        int256 referencePrice;
        uint256 deviationThresholdBps;
        BreakerState state;
        string triggerReason;
        bool registered;
    }

    mapping(address => TokenConfig) private _configs;
    uint256 private _globalThresholdBps;

    // ─── Constructor ────────────────────────────────────────────────
    constructor(address initialOwner) Ownable(initialOwner) {
        _globalThresholdBps = DEFAULT_THRESHOLD_BPS;
    }

    // ─── External Functions ─────────────────────────────────────────

    /// @notice Register a token with its Chainlink price feed
    function registerToken(address token, address priceFeed) external onlyOwner {
        SafetyChecks.requireNonZero(token);
        SafetyChecks.requireNonZero(priceFeed);

        (, int256 price,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
        require(price > 0, "CircuitBreaker: invalid price");

        _configs[token] = TokenConfig({
            priceFeed: AggregatorV3Interface(priceFeed),
            referencePrice: price,
            deviationThresholdBps: _globalThresholdBps,
            state: BreakerState.ACTIVE,
            triggerReason: "",
            registered: true
        });
    }

    /// @inheritdoc ICircuitBreaker
    function isHalted(address token) external view returns (bool) {
        return _configs[token].state == BreakerState.TRIGGERED;
    }

    /// @inheritdoc ICircuitBreaker
    function getState(address token) external view returns (BreakerState) {
        return _configs[token].state;
    }

    /// @inheritdoc ICircuitBreaker
    function triggerBreaker(address token, string calldata reason) external onlyOwner {
        TokenConfig storage config = _configs[token];
        require(config.registered, "CircuitBreaker: not registered");

        BreakerState prevState = config.state;
        if (prevState == BreakerState.TRIGGERED) revert InvalidStateTransition(prevState, BreakerState.TRIGGERED);

        config.state = BreakerState.TRIGGERED;
        config.triggerReason = reason;

        emit BreakerTriggered(token, 0, reason);
    }

    /// @inheritdoc ICircuitBreaker
    function resolveBreaker(address token) external onlyOwner {
        TokenConfig storage config = _configs[token];
        require(config.registered, "CircuitBreaker: not registered");

        if (config.state != BreakerState.TRIGGERED) {
            revert InvalidStateTransition(config.state, BreakerState.RESOLVED);
        }

        // Update reference price to current oracle price
        (, int256 newPrice,,,) = config.priceFeed.latestRoundData();
        if (newPrice > 0) {
            config.referencePrice = newPrice;
        }

        config.state = BreakerState.RESOLVED;
        config.triggerReason = "";

        emit BreakerResolved(token);
    }

    /// @inheritdoc ICircuitBreaker
    function resetBreaker(address token) external onlyOwner {
        TokenConfig storage config = _configs[token];
        require(config.registered, "CircuitBreaker: not registered");

        if (config.state != BreakerState.RESOLVED) {
            revert InvalidStateTransition(config.state, BreakerState.ACTIVE);
        }

        config.state = BreakerState.ACTIVE;
        emit BreakerReset(token);
    }

    /// @inheritdoc ICircuitBreaker
    function updateDeviationThreshold(uint256 newThresholdBps) external onlyOwner {
        SafetyChecks.requireValidThreshold(newThresholdBps);
        uint256 oldThreshold = _globalThresholdBps;
        _globalThresholdBps = newThresholdBps;
        emit DeviationThresholdUpdated(oldThreshold, newThresholdBps);
    }

    /// @inheritdoc ICircuitBreaker
    function checkPriceDeviation(address token) external view returns (uint256 deviationBps) {
        TokenConfig memory config = _configs[token];
        require(config.registered, "CircuitBreaker: not registered");

        (, int256 currentPrice,,,) = config.priceFeed.latestRoundData();
        require(currentPrice > 0, "CircuitBreaker: invalid current price");
        require(config.referencePrice > 0, "CircuitBreaker: invalid reference price");

        // Calculate absolute deviation in basis points
        // deviationBps = |current - reference| * 10000 / reference
        int256 diff = currentPrice > config.referencePrice
            ? currentPrice - config.referencePrice
            : config.referencePrice - currentPrice;

        deviationBps = (uint256(diff) * 10_000) / uint256(config.referencePrice);
    }

    /// @notice Auto-check and trigger breaker if deviation exceeds threshold
    /// @dev Called by keeper bots or governance before critical operations
    function autoTriggerIfNeeded(address token) external returns (bool wasTriggered) {
        TokenConfig storage config = _configs[token];
        require(config.registered, "CircuitBreaker: not registered");

        if (config.state != BreakerState.ACTIVE) return false;

        uint256 deviation = this.checkPriceDeviation(token);
        if (deviation >= _globalThresholdBps) {
            config.state = BreakerState.TRIGGERED;
            config.triggerReason = "Auto: price deviation exceeded threshold";
            emit BreakerTriggered(token, deviation, config.triggerReason);
            return true;
        }

        return false;
    }

    /// @notice Update the reference price for a token to current oracle price
    function updateReferencePrice(address token) external onlyOwner {
        TokenConfig storage config = _configs[token];
        require(config.registered, "CircuitBreaker: not registered");

        (, int256 newPrice,,,) = config.priceFeed.latestRoundData();
        require(newPrice > 0, "CircuitBreaker: invalid price");
        config.referencePrice = newPrice;
    }
}