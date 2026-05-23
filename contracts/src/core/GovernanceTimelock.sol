// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernanceTimelock} from "../interfaces/IGovernanceTimelock.sol";

/// @title GovernanceTimelock — Time-delayed execution for privileged operations
/// @notice All admin changes (pausing, feed updates, threshold changes) must pass through this contract
contract GovernanceTimelock is IGovernanceTimelock, Ownable {
    // ─── Constants ──────────────────────────────────────────────────
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MAX_DELAY = 30 days;

    // ─── Storage ────────────────────────────────────────────────────
    uint256 private _minDelay;
    mapping(bytes32 => Operation) private _operations;

    struct Operation {
        address target;
        bytes data;
        uint256 executeAfter;
        uint256 executeBefore;
        OperationState state;
    }

    // ─── Modifiers ──────────────────────────────────────────────────
    modifier onlyPendingOp(bytes32 id) {
        if (_operations[id].state != OperationState.SCHEDULED) revert OperationNotFound(id);
        _;
    }

    // ─── Constructor ────────────────────────────────────────────────
    /// @param initialOwner Address that can schedule/execute operations
    /// @param minDelay_ Minimum delay in seconds before an operation can be executed
    constructor(address initialOwner, uint256 minDelay_) Ownable(initialOwner) {
        require(minDelay_ <= MAX_DELAY, "GovernanceTimelock: delay exceeds max");
        _minDelay = minDelay_;
    }

    // ─── External Functions ─────────────────────────────────────────

    /// @inheritdoc IGovernanceTimelock
    function schedule(address target, bytes calldata data, uint256 delay)
        external
        onlyOwner
        returns (bytes32)
    {
        bytes32 id = _computeId(target, data);
        if (_operations[id].state != OperationState.NON_EXISTENT) revert OperationAlreadyExists(id);

        uint256 effectiveDelay = delay == 0 ? _minDelay : delay;
        require(effectiveDelay >= _minDelay, "GovernanceTimelock: delay below minimum");

        uint256 executeAfter = block.timestamp + effectiveDelay;
        uint256 executeBefore = executeAfter + GRACE_PERIOD;

        _operations[id] = Operation({
            target: target,
            data: data,
            executeAfter: executeAfter,
            executeBefore: executeBefore,
            state: OperationState.SCHEDULED
        });

        emit OperationScheduled(id, target, executeAfter);
        return id;
    }

    /// @inheritdoc IGovernanceTimelock
    function execute(address target, bytes calldata data) external onlyPendingOp(_computeId(target, data)) {
        bytes32 id = _computeId(target, data);
        Operation storage op = _operations[id];

        // ── CHECKS ──
        if (block.timestamp < op.executeAfter) revert OperationNotReady(id);
        if (block.timestamp > op.executeBefore) revert OperationExpired(id);

        // ── EFFECTS ──
        op.state = OperationState.EXECUTED;

        // ── INTERACTIONS ──
        (bool success,) = target.call(data);
        require(success, "GovernanceTimelock: execution failed");

        emit OperationExecuted(id);
    }

    /// @inheritdoc IGovernanceTimelock
    function cancel(address target, bytes calldata data) external onlyOwner onlyPendingOp(_computeId(target, data)) {
        bytes32 id = _computeId(target, data);
        _operations[id].state = OperationState.CANCELLED;
        emit OperationCancelled(id);
    }

    /// @inheritdoc IGovernanceTimelock
    function getState(address target, bytes calldata data) external view returns (OperationState) {
        return _operations[_computeId(target, data)].state;
    }

    /// @inheritdoc IGovernanceTimelock
    function minDelay() external view returns (uint256) {
        return _minDelay;
    }

    /// @notice Update the minimum delay (must go through timelock itself in production)
    function updateDelay(uint256 newDelay) external onlyOwner {
        require(newDelay <= MAX_DELAY, "GovernanceTimelock: delay exceeds max");
        uint256 oldDelay = _minDelay;
        _minDelay = newDelay;
        emit DelayUpdated(oldDelay, newDelay);
    }

    // ─── Internal Helpers ───────────────────────────────────────────

    function _computeId(address target, bytes calldata data) internal pure returns (bytes32) {
        return keccak256(abi.encode(target, data));
    }
}