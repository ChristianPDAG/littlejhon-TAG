// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IComplianceRegistry} from "../interfaces/IComplianceRegistry.sol";
import {IProofOfReserve} from "../interfaces/IProofOfReserve.sol";
import {ICircuitBreaker} from "../interfaces/ICircuitBreaker.sol";
import {SafetyChecks} from "../libraries/SafetyChecks.sol";

/// @title SafetyVault — Secure RWA asset custody with multi-layer validation
/// @notice Holds tokenized RWA assets and enforces compliance + reserve + circuit breaker checks
/// @dev Uses EIP-1153 transient storage for gas-efficient reentrancy guard (via OpenZeppelin v5)
contract SafetyVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Errors ─────────────────────────────────────────────────────
    error DepositExceedsCap(uint256 cap, uint256 attempted);
    error WithdrawalExceedsBalance(uint256 available, uint256 requested);
    error TokenNotAllowed(address token);
    error TokenAlreadyDrained(address token);
    error NotInEmergency(address token);
    error NoExcessAvailable(address token, uint256 requested, uint256 excess);

    // ─── Events ─────────────────────────────────────────────────────
    event Deposited(address indexed token, address indexed user, uint256 amount);
    event Withdrawn(address indexed token, address indexed user, uint256 amount);
    event TokenAllowed(address indexed token, uint256 cap);
    event TokenCapUpdated(address indexed token, uint256 newCap);
    event EmergencyDrained(address indexed token, address indexed rescueDestination, uint256 amount);
    event ExcessRescued(address indexed token, address indexed to, uint256 amount);

    // ─── Storage ────────────────────────────────────────────────────
    struct TokenInfo {
        bool allowed;
        uint256 cap;
        uint256 totalDeposited;
    }

    IComplianceRegistry public immutable complianceRegistry;
    IProofOfReserve public immutable proofOfReserve;
    ICircuitBreaker public immutable circuitBreaker;

    mapping(address => TokenInfo) public tokens;
    mapping(address => mapping(address => uint256)) public balances; // token => user => balance
    mapping(address => bool) public emergencyDrained; // token => drained (no further deposits/withdraws)

    // ─── Constructor ────────────────────────────────────────────────
    constructor(
        address initialOwner,
        address _complianceRegistry,
        address _proofOfReserve,
        address _circuitBreaker
    ) Ownable(initialOwner) {
        SafetyChecks.requireNonZero(_complianceRegistry);
        SafetyChecks.requireNonZero(_proofOfReserve);
        SafetyChecks.requireNonZero(_circuitBreaker);

        complianceRegistry = IComplianceRegistry(_complianceRegistry);
        proofOfReserve = IProofOfReserve(_proofOfReserve);
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
    }

    // ─── External Functions ─────────────────────────────────────────

    /// @notice Deposit RWA tokens into the vault
    /// @param token The RWA token address
    /// @param amount Amount to deposit
    function deposit(address token, uint256 amount) external nonReentrant {
        TokenInfo storage info = tokens[token];
        if (!info.allowed) revert TokenNotAllowed(token);
        if (emergencyDrained[token]) revert TokenAlreadyDrained(token);
        SafetyChecks.requireNonZero(amount);

        // ── CHECKS: Compliance ──
        if (!complianceRegistry.isVerified(msg.sender)) {
            revert IComplianceRegistry.IdentityNotVerified(msg.sender);
        }

        // ── CHECKS: Circuit breaker not triggered ──
        if (circuitBreaker.isHalted(token)) revert ICircuitBreaker.BreakerIsTriggered(token);

        // ── CHECKS: Deposit cap ──
        if (info.totalDeposited + amount > info.cap) {
            revert DepositExceedsCap(info.cap, info.totalDeposited + amount);
        }

        // ── EFFECTS ──
        balances[token][msg.sender] += amount;
        info.totalDeposited += amount;

        // ── INTERACTIONS ──
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(token, msg.sender, amount);
    }

    /// @notice Withdraw RWA tokens from the vault
    /// @param token The RWA token address
    /// @param amount Amount to withdraw
    function withdraw(address token, uint256 amount) external nonReentrant {
        TokenInfo storage info = tokens[token];
        if (!info.allowed) revert TokenNotAllowed(token);
        if (emergencyDrained[token]) revert TokenAlreadyDrained(token);
        SafetyChecks.requireNonZero(amount);

        // ── CHECKS: Sufficient balance ──
        if (balances[token][msg.sender] < amount) {
            revert WithdrawalExceedsBalance(balances[token][msg.sender], amount);
        }

        // ── CHECKS: Compliance still valid ──
        if (!complianceRegistry.isVerified(msg.sender)) {
            revert IComplianceRegistry.IdentityNotVerified(msg.sender);
        }

        // ── CHECKS: Circuit breaker not triggered ──
        if (circuitBreaker.isHalted(token)) revert ICircuitBreaker.BreakerIsTriggered(token);

        // ── CHECKS: Reserve verification (vault assets are backed) ──
        require(proofOfReserve.verifyReserve(token), "SafetyVault: reserve verification failed");

        // ── EFFECTS (Checks-Effects-Interactions pattern) ──
        balances[token][msg.sender] -= amount;
        info.totalDeposited -= amount;

        // ── INTERACTIONS ──
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdrawn(token, msg.sender, amount);
    }

    /// @notice Get the balance of a user for a specific token
    function balanceOf(address token, address user) external view returns (uint256) {
        return balances[token][user];
    }

    // ─── Admin Functions ────────────────────────────────────────────

    /// @notice Allow a token to be deposited in the vault
    /// @param token Token address
    /// @param cap Maximum total deposits for this token
    function allowToken(address token, uint256 cap) external onlyOwner {
        SafetyChecks.requireNonZero(token);
        SafetyChecks.requireNonZero(cap);
        tokens[token] = TokenInfo({allowed: true, cap: cap, totalDeposited: 0});
        emit TokenAllowed(token, cap);
    }

    /// @notice Update the deposit cap for a token
    function updateTokenCap(address token, uint256 newCap) external onlyOwner {
        require(tokens[token].allowed, "SafetyVault: token not allowed");
        SafetyChecks.requireNonZero(newCap);
        tokens[token].cap = newCap;
        emit TokenCapUpdated(token, newCap);
    }

    /// @notice Emergency drain — moves the full token balance to a rescue destination and marks the
    ///         token as drained, permanently disabling deposits and withdraws for that token.
    /// @dev Only callable when the circuit breaker is triggered. Once drained, user `balances` are
    ///      frozen on-chain and must be honored off-chain (or via a migration contract). This is
    ///      intentional: under emergency, funds move to a multisig for custody, and the on-chain
    ///      bookkeeping is preserved as a claim record.
    function emergencyDrain(address token, address rescueDestination) external onlyOwner {
        SafetyChecks.requireNonZero(rescueDestination);
        if (!circuitBreaker.isHalted(token)) revert NotInEmergency(token);
        if (emergencyDrained[token]) revert TokenAlreadyDrained(token);

        uint256 balance = IERC20(token).balanceOf(address(this));
        emergencyDrained[token] = true;
        if (balance > 0) {
            IERC20(token).safeTransfer(rescueDestination, balance);
        }
        emit EmergencyDrained(token, rescueDestination, balance);
    }

    /// @notice Rescue tokens accidentally sent to the vault that are not backing any user balance.
    /// @dev Only the excess (contract balance minus accounted totalDeposited) can be withdrawn.
    ///      Cannot be used to seize user-deposited funds.
    function rescueExcessTokens(address token, address to, uint256 amount) external onlyOwner {
        SafetyChecks.requireNonZero(to);
        SafetyChecks.requireNonZero(amount);

        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 accounted = tokens[token].totalDeposited;
        uint256 excess = balance > accounted ? balance - accounted : 0;
        if (amount > excess) revert NoExcessAvailable(token, amount, excess);

        IERC20(token).safeTransfer(to, amount);
        emit ExcessRescued(token, to, amount);
    }
}