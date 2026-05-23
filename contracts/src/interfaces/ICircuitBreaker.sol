// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICircuitBreaker — Emergency pause mechanism for anomalous conditions
/// @notice Monitors price deviations and triggers automatic halts on withdrawals/transfers
interface ICircuitBreaker {
    /// @dev Circuit breaker states
    enum BreakerState {
        ACTIVE,      // Normal operations
        TRIGGERED,   // Anomaly detected — operations paused
        RESOLVED     // Issue resolved — ready to reactivate
    }

    /// @dev Emitted when breaker state changes
    event BreakerTriggered(address indexed token, uint256 deviationBps, string reason);
    event BreakerResolved(address indexed token);
    event BreakerReset(address indexed token);
    event DeviationThresholdUpdated(uint256 oldThresholdBps, uint256 newThresholdBps);

    /// @dev Custom errors
    error BreakerIsTriggered(address token);
    error InvalidStateTransition(BreakerState from, BreakerState to);

    /// @notice Check if operations are halted for a token
    /// @return halted True if the breaker is in TRIGGERED state
    function isHalted(address token) external view returns (bool);

    /// @notice Get the current state of the breaker for a token
    function getState(address token) external view returns (BreakerState);

    /// @notice Trigger the breaker manually (governance only)
    /// @param token The asset to halt
    /// @param reason Human-readable reason for the halt
    function triggerBreaker(address token, string calldata reason) external;

    /// @notice Resolve a triggered breaker (governance only)
    function resolveBreaker(address token) external;

    /// @notice Reset a resolved breaker back to active
    function resetBreaker(address token) external;

    /// @notice Update the deviation threshold that auto-triggers the breaker
    /// @param newThresholdBps New threshold in basis points (e.g., 1500 = 15%)
    function updateDeviationThreshold(uint256 newThresholdBps) external;

    /// @notice Verify price deviation for a token against its oracle
    /// @return deviationBps The current deviation in basis points
    function checkPriceDeviation(address token) external view returns (uint256 deviationBps);
}