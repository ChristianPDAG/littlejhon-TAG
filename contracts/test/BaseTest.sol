// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {ComplianceRegistry} from "../src/core/ComplianceRegistry.sol";
import {ProofOfReserve} from "../src/core/ProofOfReserve.sol";
import {CircuitBreaker} from "../src/core/CircuitBreaker.sol";
import {SafetyVault} from "../src/core/SafetyVault.sol";
import {ShieldRWAGuard} from "../src/ShieldRWAGuard.sol";
import {GovernanceTimelock} from "../src/core/GovernanceTimelock.sol";

/// @title BaseTest — Shared setup for all test contracts
abstract contract BaseTest is Test {
    // ─── Actors ─────────────────────────────────────────────────────
    address public owner;
    address public alice;
    address public bob;
    address public carol;
    address public unauthorized;
    address public trustedSigner;
    uint256 internal trustedSignerPk;

    // ─── Contracts ──────────────────────────────────────────────────
    MockERC20 public rwaToken;
    MockOracle public priceOracle;
    MockOracle public porOracle;
    ComplianceRegistry public compliance;
    ProofOfReserve public por;
    CircuitBreaker public breaker;
    SafetyVault public vault;
    ShieldRWAGuard public guard;
    GovernanceTimelock public timelock;

    // ─── Constants ──────────────────────────────────────────────────
    uint256 constant INITIAL_PRICE = 150_000_000_000; // $150.00 (8 decimals)
    uint256 constant INITIAL_RESERVES = 10_000_000 * 1e18;
    uint256 constant TOKEN_CAP = 1_000_000 * 1e18;
    uint256 constant TRANSFER_LIMIT = 100_000 * 1e18;
    uint256 constant JURISDICTION_US = 1;
    uint256 constant JURISDICTION_EU = 2;
    uint256 constant IDENTITY_EXPIRY = 365 days;
    uint256 constant TIMELOCK_DELAY = 1 days;
    uint256 constant MAX_RISK_SCORE = 75;
    uint256 constant DEFAULT_RISK_SCORE = 10;

    // ─── EIP-712 Constants ──────────────────────────────────────────
    bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant TRANSFER_TYPEHASH = keccak256("ShieldTransfer(address token,address from,address to,uint256 amount,uint256 nonce,uint256 deadline)");
    bytes32 constant RISK_ATTESTATION_TYPEHASH = keccak256(
        "RiskAttestation(address token,address from,address to,uint256 amount,uint256 nonce,uint256 deadline,uint256 riskScore)"
    );

    function setUp() public virtual {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        unauthorized = makeAddr("unauthorized");

        trustedSignerPk = 0xB4CE; // backend risk-engine wallet
        trustedSigner = vm.addr(trustedSignerPk);

        vm.startPrank(owner);

        // Deploy mock tokens and oracles
        rwaToken = new MockERC20("TSLA Token", "TSLA");
        priceOracle = new MockOracle(8, "TSLA/USD");
        porOracle = new MockOracle(18, "TSLA PoR");

        // Set initial oracle prices
        priceOracle.setPrice(int256(INITIAL_PRICE));
        porOracle.setPrice(int256(INITIAL_RESERVES));

        // Deploy core contracts
        compliance = new ComplianceRegistry(owner);
        por = new ProofOfReserve(owner);
        breaker = new CircuitBreaker(owner);
        timelock = new GovernanceTimelock(owner, TIMELOCK_DELAY);

        // Deploy vault
        vault = new SafetyVault(owner, address(compliance), address(por), address(breaker));

        // Deploy ShieldRWAGuard with trusted backend signer + risk cap
        guard = new ShieldRWAGuard(
            owner,
            address(compliance),
            address(por),
            address(breaker),
            trustedSigner,
            MAX_RISK_SCORE
        );

        // Configure Proof of Reserve
        por.registerFeed(address(rwaToken), address(porOracle), 1 hours);

        // Configure Circuit Breaker
        breaker.registerToken(address(rwaToken), address(priceOracle));

        // Whitelist token in ShieldRWAGuard
        guard.whitelistToken(address(rwaToken), TRANSFER_LIMIT);

        // Allow token in vault
        vault.allowToken(address(rwaToken), TOKEN_CAP);

        // Verify identities
        compliance.verifyIdentity(alice, JURISDICTION_US, block.timestamp + IDENTITY_EXPIRY);
        compliance.verifyIdentity(bob, JURISDICTION_EU, block.timestamp + IDENTITY_EXPIRY);
        compliance.verifyIdentity(carol, JURISDICTION_US, block.timestamp + IDENTITY_EXPIRY);

        vm.stopPrank();

        // Distribute tokens
        vm.prank(owner);
        rwaToken.transfer(alice, 50_000 * 1e18);
        vm.prank(owner);
        rwaToken.transfer(bob, 50_000 * 1e18);
    }

    // ─── Helpers: EIP-712 Signatures ────────────────────────────────

    function _guardDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("ShieldRWAGuard"), keccak256("1"), block.chainid, address(guard))
        );
    }

    function _signTransfer(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(TRANSFER_TYPEHASH, token, from, to, amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _guardDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Builds the EIP-712 RiskAttestation signature from the backend's trusted signer.
    function _signAttestation(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 riskScore,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(RISK_ATTESTATION_TYPEHASH, token, from, to, amount, nonce, deadline, riskScore)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _guardDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }
}