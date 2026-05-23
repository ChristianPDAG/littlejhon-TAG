// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IGovernanceTimelock — Time-delayed governance for sensitive operations
/// @notice Ensures all admin actions go through a delay period before execution
interface IGovernanceTimelock {
    /// @dev Operation states
    enum OperationState {
        NON_EXISTENT,
        SCHEDULED,
        EXECUTED,
        CANCELLED
    }

    /// @dev Emitted when operations are scheduled, executed, or cancelled
    event OperationScheduled(bytes32 indexed operationId, address indexed target, uint256 executeAfter);
    event OperationExecuted(bytes32 indexed operationId);
    event OperationCancelled(bytes32 indexed operationId);
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);

    /// @dev Custom errors
    error OperationNotReady(bytes32 operationId);
    error OperationExpired(bytes32 operationId);
    error OperationAlreadyExists(bytes32 operationId);
    error OperationNotFound(bytes32 operationId);

    /// @notice Schedule a governance operation
    /// @param target Contract to call
    /// @param data Calldata for the call
    /// @param delay Override delay (must be >= minDelay), or 0 for default
    /// @return operationId Unique identifier for this operation
    function schedule(address target, bytes calldata data, uint256 delay) external returns (bytes32);

    /// @notice Execute a previously scheduled operation
    /// @param target Contract to call
    /// @param data Calldata (must match scheduled)
    function execute(address target, bytes calldata data) external;

    /// @notice Cancel a pending operation
    function cancel(address target, bytes calldata data) external;

    /// @notice Check the state of an operation
    function getState(address target, bytes calldata data) external view returns (OperationState);

    /// @notice Get the minimum delay
    function minDelay() external view returns (uint256);
}