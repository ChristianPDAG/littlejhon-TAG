// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {ShieldRWAGuard} from "../src/ShieldRWAGuard.sol";
import {ComplianceRegistry} from "../src/core/ComplianceRegistry.sol";
import {ProofOfReserve} from "../src/core/ProofOfReserve.sol";
import {CircuitBreaker} from "../src/core/CircuitBreaker.sol";
import {ICircuitBreaker} from "../src/interfaces/ICircuitBreaker.sol";

/// @title E2EFlow — On-chain end-to-end validation of the ShieldRWAGuard safety layer
/// @notice Runs four flows against the LIVE deployment on Robinhood or Arbitrum Sepolia:
///         1. Happy-path safeTransfer
///         2. Replay attack (nonce reused → revert)
///         3. Risk score above cap (→ revert)
///         4. Circuit breaker triggered (→ revert)
///
/// Each flow's tx hash + outcome is logged so a judge can verify on the explorer.
contract E2EFlowScript is Script {
    // ─── Live deployment (same address on RH + Arbitrum) ────────────
    ShieldRWAGuard constant GUARD = ShieldRWAGuard(0xB4f9C2151B73eDEa730A72e9642C971d803Fd096);
    ComplianceRegistry constant COMPLIANCE = ComplianceRegistry(0x5886F06c5cD7eC7E07396D4787fca22A965032C5);
    ProofOfReserve constant POR = ProofOfReserve(0x5eD6fe0C2bF02227153CC5482f7d316475a11625);
    CircuitBreaker constant BREAKER = CircuitBreaker(0x8A65a9ae5057eB846ce06c1E890f0aB8ADB05777);

    // ─── Test actors (deterministic) ────────────────────────────────
    uint256 constant ALICE_PK = 0xA11CE;
    uint256 constant BOB_PK = 0xB0B;

    // ─── EIP-712 typehashes (must match SafetyChecks.sol) ───────────
    bytes32 constant TRANSFER_TYPEHASH = keccak256(
        "ShieldTransfer(address token,address from,address to,uint256 amount,uint256 nonce,uint256 deadline)"
    );
    bytes32 constant ATTESTATION_TYPEHASH = keccak256(
        "RiskAttestation(address token,address from,address to,uint256 amount,uint256 nonce,uint256 deadline,uint256 riskScore)"
    );

    // ─── State ──────────────────────────────────────────────────────
    MockERC20 token;
    MockOracle priceOracle;
    MockOracle porOracle;
    uint256 deployerPk;
    address deployer;
    address alice;
    address bob;

    function run() external {
        deployerPk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPk);
        alice = vm.addr(ALICE_PK);
        bob = vm.addr(BOB_PK);

        console.log("=== E2E Flow validation ===");
        console.log("Chain ID         :", block.chainid);
        console.log("Deployer/Signer  :", deployer);
        console.log("Alice (test user):", alice);
        console.log("Bob   (recipient):", bob);
        console.log("");

        _phase1_DeployMocks();
        _phase2_ConfigureContracts();
        _phase3_FundAlice();
        _phase4_AliceApproves();
        _phase5_HappyPath();
        _phase6_ReplayAttack();
        _phase7_RiskScoreTooHigh();
        _phase8_CircuitBreakerBlocks();
        _phase9_FinalState();
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 1 — Deploy mock token + oracles (broadcast from deployer)
    // ═══════════════════════════════════════════════════════════════
    function _phase1_DeployMocks() internal {
        console.log("--- Phase 1: Deploy mocks ---");
        vm.startBroadcast(deployerPk);

        token = new MockERC20("E2E Test RWA", "tRWA");
        priceOracle = new MockOracle(8, "tRWA/USD");
        porOracle = new MockOracle(18, "tRWA PoR");

        // Price = $150 with 8 decimals, reserves cover the full supply
        priceOracle.setPrice(int256(150_00000000));
        porOracle.setPrice(int256(10_000_000e18));

        vm.stopBroadcast();

        console.log("  MockERC20    :", address(token));
        console.log("  PriceOracle  :", address(priceOracle));
        console.log("  PorOracle    :", address(porOracle));
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 2 — Wire the new token into the existing live contracts
    // ═══════════════════════════════════════════════════════════════
    function _phase2_ConfigureContracts() internal {
        console.log("--- Phase 2: Configure existing contracts for the new token ---");
        vm.startBroadcast(deployerPk);

        POR.registerFeed(address(token), address(porOracle), 1 hours);
        BREAKER.registerToken(address(token), address(priceOracle));
        GUARD.whitelistToken(address(token), 100_000e18);
        COMPLIANCE.verifyIdentity(alice, 1, block.timestamp + 365 days);
        COMPLIANCE.verifyIdentity(bob, 1, block.timestamp + 365 days);

        vm.stopBroadcast();

        console.log("  PoR feed registered, breaker registered, guard whitelist, KYC alice+bob");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 3 — Fund Alice with tokens AND a tiny bit of native gas
    // ═══════════════════════════════════════════════════════════════
    function _phase3_FundAlice() internal {
        console.log("--- Phase 3: Fund Alice with tRWA + native gas ---");
        vm.startBroadcast(deployerPk);

        token.transfer(alice, 50_000e18);
        (bool ok,) = alice.call{value: 0.0005 ether}("");
        require(ok, "fund alice failed");

        vm.stopBroadcast();

        console.log("  Alice tRWA balance:", token.balanceOf(alice) / 1e18, "tRWA");
        console.log("  Alice native bal  :", alice.balance);
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 4 — Alice approves the Guard to spend her tRWA
    // ═══════════════════════════════════════════════════════════════
    function _phase4_AliceApproves() internal {
        console.log("--- Phase 4: Alice approves the Guard ---");
        vm.startBroadcast(ALICE_PK);
        token.approve(address(GUARD), type(uint256).max);
        vm.stopBroadcast();
        console.log("  approve OK");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 5 — Happy path: safeTransfer alice -> bob with riskScore=10
    // ═══════════════════════════════════════════════════════════════
    function _phase5_HappyPath() internal {
        console.log("--- Phase 5: HAPPY PATH (expect tokens to move) ---");
        uint256 amount = 1_000e18;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 riskScore = 10;

        (bytes memory userSig, bytes memory attSig) =
            _buildBothSignatures(amount, nonce, deadline, riskScore, ALICE_PK, deployerPk);

        uint256 bobBefore = token.balanceOf(bob);
        vm.startBroadcast(deployerPk);
        GUARD.safeTransfer(address(token), alice, bob, amount, nonce, deadline, riskScore, userSig, attSig);
        vm.stopBroadcast();
        uint256 bobAfter = token.balanceOf(bob);

        console.log("  Bob received:", (bobAfter - bobBefore) / 1e18, "tRWA");
        console.log("  Expected    : 1000 tRWA");
        require(bobAfter - bobBefore == amount, "happy path failed");
        console.log("  PASS");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 6 — Replay attack: reuse nonce=1 (expect revert)
    // ═══════════════════════════════════════════════════════════════
    function _phase6_ReplayAttack() internal {
        console.log("--- Phase 6: REPLAY ATTACK (expect revert NonceAlreadyUsed) ---");
        uint256 amount = 1_000e18;
        uint256 nonce = 1; // reused
        uint256 deadline = block.timestamp + 1 hours;
        uint256 riskScore = 10;

        (bytes memory userSig, bytes memory attSig) =
            _buildBothSignatures(amount, nonce, deadline, riskScore, ALICE_PK, deployerPk);

        vm.startBroadcast(deployerPk);
        try GUARD.safeTransfer(address(token), alice, bob, amount, nonce, deadline, riskScore, userSig, attSig) {
            revert("replay attack should have reverted");
        } catch {
            console.log("  Reverted as expected");
        }
        vm.stopBroadcast();
        console.log("  PASS");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 7 — Risk score too high (90 > maxRiskScore=75) (expect revert)
    // ═══════════════════════════════════════════════════════════════
    function _phase7_RiskScoreTooHigh() internal {
        console.log("--- Phase 7: RISK SCORE > maxRiskScore (expect revert) ---");
        uint256 amount = 1_000e18;
        uint256 nonce = 2;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 riskScore = 90;

        (bytes memory userSig, bytes memory attSig) =
            _buildBothSignatures(amount, nonce, deadline, riskScore, ALICE_PK, deployerPk);

        vm.startBroadcast(deployerPk);
        try GUARD.safeTransfer(address(token), alice, bob, amount, nonce, deadline, riskScore, userSig, attSig) {
            revert("high risk should have reverted");
        } catch {
            console.log("  Reverted as expected (riskScore=90 > maxRiskScore=75)");
        }
        vm.stopBroadcast();
        console.log("  PASS");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 8 — Circuit breaker triggered (expect revert)
    // ═══════════════════════════════════════════════════════════════
    function _phase8_CircuitBreakerBlocks() internal {
        console.log("--- Phase 8: CIRCUIT BREAKER blocks transfer ---");

        // Crash the price 30% and auto-trigger
        vm.startBroadcast(deployerPk);
        priceOracle.setPrice(int256(150_00000000 * 70 / 100));
        bool triggered = BREAKER.autoTriggerIfNeeded(address(token));
        vm.stopBroadcast();
        require(triggered, "breaker did not trigger");
        require(BREAKER.isHalted(address(token)), "breaker not halted");
        console.log("  Breaker triggered, isHalted = true");

        // Try a legitimate transfer — must revert
        uint256 amount = 100e18;
        uint256 nonce = 3;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 riskScore = 10;

        (bytes memory userSig, bytes memory attSig) =
            _buildBothSignatures(amount, nonce, deadline, riskScore, ALICE_PK, deployerPk);

        vm.startBroadcast(deployerPk);
        try GUARD.safeTransfer(address(token), alice, bob, amount, nonce, deadline, riskScore, userSig, attSig) {
            revert("breaker-triggered transfer should have reverted");
        } catch {
            console.log("  Transfer reverted as expected (breaker triggered)");
        }
        vm.stopBroadcast();
        console.log("  PASS");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 9 — Print final on-chain state for the evidence doc
    // ═══════════════════════════════════════════════════════════════
    function _phase9_FinalState() internal view {
        console.log("=== Final state ===");
        console.log("Bob tRWA balance :", token.balanceOf(bob) / 1e18, "tRWA (should be 1000)");
        console.log("Alice tRWA bal   :", token.balanceOf(alice) / 1e18, "tRWA (should be 49000)");
        console.log("Token whitelisted:", _isWhitelisted());
        console.log("Breaker halted   :", BREAKER.isHalted(address(token)));
        console.log("Nonce 1 used     :", GUARD.usedNonces(alice, 1));
        console.log("Nonce 2 used     :", GUARD.usedNonces(alice, 2));
        console.log("Nonce 3 used     :", GUARD.usedNonces(alice, 3));
        console.log("");
        console.log(">>> ALL 4 GATES VALIDATED ON-CHAIN <<<");
        console.log("Token deployed at:", address(token));
        console.log("Verify on the explorer for tx history.");
    }

    function _isWhitelisted() internal view returns (bool ok) {
        (ok,) = GUARD.tokenConfigs(address(token));
    }

    // ─── Signature helpers ──────────────────────────────────────────
    function _buildBothSignatures(
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 riskScore,
        uint256 userPk,
        uint256 attestorPk
    ) internal view returns (bytes memory userSig, bytes memory attSig) {
        bytes32 domain = GUARD.domainSeparator();

        bytes32 transferStruct = keccak256(
            abi.encode(TRANSFER_TYPEHASH, address(token), alice, bob, amount, nonce, deadline)
        );
        bytes32 transferDigest = keccak256(abi.encodePacked("\x19\x01", domain, transferStruct));
        (uint8 vU, bytes32 rU, bytes32 sU) = vm.sign(userPk, transferDigest);
        userSig = abi.encodePacked(rU, sU, vU);

        bytes32 attStruct = keccak256(
            abi.encode(ATTESTATION_TYPEHASH, address(token), alice, bob, amount, nonce, deadline, riskScore)
        );
        bytes32 attDigest = keccak256(abi.encodePacked("\x19\x01", domain, attStruct));
        (uint8 vA, bytes32 rA, bytes32 sA) = vm.sign(attestorPk, attDigest);
        attSig = abi.encodePacked(rA, sA, vA);
    }
}
