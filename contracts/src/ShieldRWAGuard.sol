// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IComplianceRegistry} from "./interfaces/IComplianceRegistry.sol";
import {IProofOfReserve} from "./interfaces/IProofOfReserve.sol";
import {ICircuitBreaker} from "./interfaces/ICircuitBreaker.sol";
import {SafetyChecks} from "./libraries/SafetyChecks.sol";

/// @title ShieldRWAGuard — Core Safety Layer orchestrator for RWA transfers
/// @notice Entry point that validates compliance, reserves, circuit breakers, AND an off-chain
///         risk-engine attestation before any RWA transfer can settle.
/// @dev Every transfer requires two EIP-712 signatures sharing the same nonce/deadline:
///         1. `userSig` — signed by `from`, authorizing the transfer (ShieldTransfer typehash)
///         2. `attestationSig` — signed by `trustedSigner` (the backend risk engine),
///            endorsing the transfer plus a `riskScore` enforced against `maxRiskScore`.
contract ShieldRWAGuard is Ownable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    // ─── Constants ──────────────────────────────────────────────────
    string public constant NAME = "ShieldRWAGuard";
    string public constant VERSION = "1";

    /// @notice Upper bound for any risk score the backend can emit (0-100 scale).
    uint256 public constant RISK_SCORE_SCALE = 100;

    // ─── Errors ─────────────────────────────────────────────────────
    error TokenNotWhitelisted(address token);
    error InvalidSignature(address recovered, address expected);
    error InvalidAttestation(address recovered, address expected);
    error NonceAlreadyUsed(uint256 nonce);
    error TransferExceedsLimit(uint256 limit, uint256 amount);
    error TrustedSignerNotSet();
    error RiskScoreOutOfRange(uint256 score);
    error RiskScoreTooHigh(uint256 score, uint256 max);
    error MaxRiskScoreOutOfRange(uint256 max);

    // ─── Events ─────────────────────────────────────────────────────
    event SafeTransferExecuted(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 nonce,
        uint256 riskScore
    );
    event TokenWhitelisted(address indexed token, uint256 transferLimit);
    event TokenDelisted(address indexed token);
    event TransferLimitUpdated(address indexed token, uint256 newLimit);
    event NonceConsumed(address indexed user, uint256 nonce);
    event TrustedSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event MaxRiskScoreUpdated(uint256 oldMax, uint256 newMax);

    // ─── Storage ────────────────────────────────────────────────────
    struct TokenConfig {
        bool whitelisted;
        uint256 transferLimit; // Max transfer per tx per token (0 = unlimited)
    }

    IComplianceRegistry public immutable complianceRegistry;
    IProofOfReserve public immutable proofOfReserve;
    ICircuitBreaker public immutable circuitBreaker;

    /// @notice Address whose EIP-712 signatures over RiskAttestation are accepted.
    address public trustedSigner;
    /// @notice Inclusive upper bound on riskScore the contract will accept (0-100).
    uint256 public maxRiskScore;

    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => mapping(uint256 => bool)) public usedNonces; // user => nonce => used

    // ─── Constructor ────────────────────────────────────────────────
    constructor(
        address initialOwner,
        address _complianceRegistry,
        address _proofOfReserve,
        address _circuitBreaker,
        address _trustedSigner,
        uint256 _maxRiskScore
    ) Ownable(initialOwner) EIP712(NAME, VERSION) {
        SafetyChecks.requireNonZero(_complianceRegistry);
        SafetyChecks.requireNonZero(_proofOfReserve);
        SafetyChecks.requireNonZero(_circuitBreaker);
        SafetyChecks.requireNonZero(_trustedSigner);
        if (_maxRiskScore > RISK_SCORE_SCALE) revert MaxRiskScoreOutOfRange(_maxRiskScore);

        complianceRegistry = IComplianceRegistry(_complianceRegistry);
        proofOfReserve = IProofOfReserve(_proofOfReserve);
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
        trustedSigner = _trustedSigner;
        maxRiskScore = _maxRiskScore;

        emit TrustedSignerUpdated(address(0), _trustedSigner);
        emit MaxRiskScoreUpdated(0, _maxRiskScore);
    }

    // ─── External Functions ─────────────────────────────────────────

    /// @notice Execute a validated RWA transfer requiring BOTH the user's signature and a
    ///         risk-engine attestation. Both signatures share the same nonce/deadline; the
    ///         single nonce protects against replay for the whole bundle.
    /// @param token The RWA token to transfer.
    /// @param from The sender (must have signed `userSig`).
    /// @param to The recipient.
    /// @param amount Amount to transfer.
    /// @param nonce Unique nonce per (from) for replay protection — consumed on success.
    /// @param deadline Signature expiration timestamp (shared by both signatures).
    /// @param riskScore Score asserted by the backend (0-100). Must be ≤ maxRiskScore.
    /// @param userSig EIP-712 signature from `from` over ShieldTransfer.
    /// @param attestationSig EIP-712 signature from `trustedSigner` over RiskAttestation.
    function safeTransfer(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 riskScore,
        bytes calldata userSig,
        bytes calldata attestationSig
    ) external nonReentrant {
        // ═══ CHECKS ═══

        // 1. Token must be whitelisted
        if (!tokenConfigs[token].whitelisted) revert TokenNotWhitelisted(token);

        // 2. Amount + recipient validation
        SafetyChecks.requireNonZero(amount);
        SafetyChecks.requireNonZero(to);

        // 3. Deadline must not be expired
        SafetyChecks.requireNotExpired(deadline);

        // 4. Nonce must not be reused
        if (usedNonces[from][nonce]) revert NonceAlreadyUsed(nonce);

        // 5. Risk score must be within absolute scale AND within the accepted cap
        if (riskScore > RISK_SCORE_SCALE) revert RiskScoreOutOfRange(riskScore);
        if (riskScore > maxRiskScore) revert RiskScoreTooHigh(riskScore, maxRiskScore);

        // 6. Trusted signer must be configured (defensive — constructor already enforces this,
        //    but a future setTrustedSigner(0) would be caught here too).
        address signer = trustedSigner;
        if (signer == address(0)) revert TrustedSignerNotSet();

        // 7. Verify user signature against `from`
        {
            bytes32 transferHash = SafetyChecks.computeTransferStructHash(token, from, to, amount, nonce, deadline);
            bytes32 transferDigest = _hashTypedDataV4(transferHash);
            (bytes32 r, bytes32 s, uint8 v) = SafetyChecks.parseSignature(userSig);
            address recoveredUser = ecrecover(transferDigest, v, r, s);
            if (recoveredUser != from || recoveredUser == address(0)) {
                revert InvalidSignature(recoveredUser, from);
            }
        }

        // 8. Verify attestation signature against `trustedSigner`
        {
            bytes32 attestationHash = SafetyChecks.computeAttestationStructHash(
                token, from, to, amount, nonce, deadline, riskScore
            );
            bytes32 attestationDigest = _hashTypedDataV4(attestationHash);
            (bytes32 r, bytes32 s, uint8 v) = SafetyChecks.parseSignature(attestationSig);
            address recoveredAttestor = ecrecover(attestationDigest, v, r, s);
            if (recoveredAttestor != signer || recoveredAttestor == address(0)) {
                revert InvalidAttestation(recoveredAttestor, signer);
            }
        }

        // 9. Compliance: both sender and receiver must be verified
        if (!complianceRegistry.isVerified(from)) {
            revert IComplianceRegistry.IdentityNotVerified(from);
        }
        if (!complianceRegistry.isVerified(to)) {
            revert IComplianceRegistry.IdentityNotVerified(to);
        }

        // 10. Circuit breaker must not be triggered
        if (circuitBreaker.isHalted(token)) revert ICircuitBreaker.BreakerIsTriggered(token);

        // 11. Proof of Reserve must verify backing
        require(proofOfReserve.verifyReserve(token), "ShieldRWAGuard: reserve verification failed");

        // 12. Transfer limit check
        uint256 limit = tokenConfigs[token].transferLimit;
        if (limit > 0 && amount > limit) revert TransferExceedsLimit(limit, amount);

        // ═══ EFFECTS ═══
        usedNonces[from][nonce] = true;
        emit NonceConsumed(from, nonce);

        // ═══ INTERACTIONS ═══
        IERC20(token).safeTransferFrom(from, to, amount);

        emit SafeTransferExecuted(token, from, to, amount, nonce, riskScore);
    }

    /// @notice Check if a transfer would pass all safety checks (view-only simulation).
    /// @dev Does not verify signatures — it only sanity-checks state. PoR is skipped to keep
    ///      this cheap for UIs; the riskScore cap and trusted-signer presence ARE evaluated.
    function canSafeTransfer(address token, address from, address to, uint256 amount, uint256 riskScore)
        external
        view
        returns (bool canTransfer, string memory reason)
    {
        if (!tokenConfigs[token].whitelisted) return (false, "Token not whitelisted");
        if (amount == 0) return (false, "Zero amount");
        if (to == address(0)) return (false, "Zero address recipient");
        if (trustedSigner == address(0)) return (false, "Trusted signer not set");
        if (riskScore > RISK_SCORE_SCALE) return (false, "Risk score out of range");
        if (riskScore > maxRiskScore) return (false, "Risk score exceeds cap");

        if (!complianceRegistry.isVerified(from)) return (false, "Sender not verified");
        if (!complianceRegistry.isVerified(to)) return (false, "Recipient not verified");
        if (circuitBreaker.isHalted(token)) return (false, "Circuit breaker triggered");

        uint256 limit = tokenConfigs[token].transferLimit;
        if (limit > 0 && amount > limit) return (false, "Transfer exceeds limit");

        return (true, "All checks passed");
    }

    /// @notice Expose the EIP-712 domain separator (handy for off-chain signers).
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ─── Admin Functions ────────────────────────────────────────────

    /// @notice Whitelist a token for safe transfers
    function whitelistToken(address token, uint256 transferLimit) external onlyOwner {
        SafetyChecks.requireNonZero(token);
        tokenConfigs[token] = TokenConfig({whitelisted: true, transferLimit: transferLimit});
        emit TokenWhitelisted(token, transferLimit);
    }

    /// @notice Remove a token from the whitelist
    function delistToken(address token) external onlyOwner {
        tokenConfigs[token].whitelisted = false;
        emit TokenDelisted(token);
    }

    /// @notice Update the per-transfer limit for a token
    function updateTransferLimit(address token, uint256 newLimit) external onlyOwner {
        require(tokenConfigs[token].whitelisted, "ShieldRWAGuard: not whitelisted");
        tokenConfigs[token].transferLimit = newLimit;
        emit TransferLimitUpdated(token, newLimit);
    }

    /// @notice Rotate the off-chain risk-engine signer.
    function setTrustedSigner(address newSigner) external onlyOwner {
        SafetyChecks.requireNonZero(newSigner);
        address oldSigner = trustedSigner;
        trustedSigner = newSigner;
        emit TrustedSignerUpdated(oldSigner, newSigner);
    }

    /// @notice Tighten or relax the maximum acceptable risk score.
    function setMaxRiskScore(uint256 newMax) external onlyOwner {
        if (newMax > RISK_SCORE_SCALE) revert MaxRiskScoreOutOfRange(newMax);
        uint256 oldMax = maxRiskScore;
        maxRiskScore = newMax;
        emit MaxRiskScoreUpdated(oldMax, newMax);
    }
}
