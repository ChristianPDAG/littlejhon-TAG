// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ComplianceRegistry} from "../src/core/ComplianceRegistry.sol";
import {ProofOfReserve} from "../src/core/ProofOfReserve.sol";
import {CircuitBreaker} from "../src/core/CircuitBreaker.sol";
import {SafetyVault} from "../src/core/SafetyVault.sol";
import {ShieldRWAGuard} from "../src/ShieldRWAGuard.sol";
import {GovernanceTimelock} from "../src/core/GovernanceTimelock.sol";

/// @title DeployScript — Deploys the full ShieldRWAGuard Safety Layer
/// @notice Supports both Robinhood Chain Testnet and Arbitrum Sepolia
contract DeployScript is Script {
    // ─── Deployed Addresses ─────────────────────────────────────────
    ComplianceRegistry public compliance;
    ProofOfReserve public por;
    CircuitBreaker public breaker;
    SafetyVault public vault;
    ShieldRWAGuard public guard;
    GovernanceTimelock public timelock;

    // ─── Configuration ──────────────────────────────────────────────
    uint256 constant TIMELOCK_DELAY = 1 days;
    uint256 constant DEFAULT_MAX_RISK_SCORE = 75; // 0-100 scale

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        // TRUSTED_SIGNER is the public address of the backend risk-engine wallet (never the
        // private key — that lives only in the backend env). Required, no default.
        address trustedSigner = vm.envAddress("TRUSTED_SIGNER");
        require(trustedSigner != address(0), "Deploy: TRUSTED_SIGNER not set");

        // Optional override for the max risk score (0-100). Defaults to DEFAULT_MAX_RISK_SCORE.
        uint256 maxRiskScore = vm.envOr("MAX_RISK_SCORE", DEFAULT_MAX_RISK_SCORE);
        require(maxRiskScore <= 100, "Deploy: MAX_RISK_SCORE > 100");

        console.log("=== ShieldRWAGuard Safety Layer Deployment ===");
        console.log("Deployer       :", deployer);
        console.log("Chain ID       :", block.chainid);
        console.log("Balance        :", deployer.balance);
        console.log("Trusted Signer :", trustedSigner);
        console.log("Max Risk Score :", maxRiskScore);

        vm.startBroadcast(deployerPk);

        // 1. Deploy GovernanceTimelock
        timelock = new GovernanceTimelock(deployer, TIMELOCK_DELAY);
        console.log("GovernanceTimelock:", address(timelock));

        // 2. Deploy ComplianceRegistry
        compliance = new ComplianceRegistry(deployer);
        console.log("ComplianceRegistry:", address(compliance));

        // 3. Deploy ProofOfReserve
        por = new ProofOfReserve(deployer);
        console.log("ProofOfReserve:", address(por));

        // 4. Deploy CircuitBreaker
        breaker = new CircuitBreaker(deployer);
        console.log("CircuitBreaker:", address(breaker));

        // 5. Deploy SafetyVault
        vault = new SafetyVault(deployer, address(compliance), address(por), address(breaker));
        console.log("SafetyVault:", address(vault));

        // 6. Deploy ShieldRWAGuard with the trusted signer + risk cap baked in
        guard = new ShieldRWAGuard(
            deployer,
            address(compliance),
            address(por),
            address(breaker),
            trustedSigner,
            maxRiskScore
        );
        console.log("ShieldRWAGuard:", address(guard));

        vm.stopBroadcast();

        // Print summary
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("GovernanceTimelock :", address(timelock));
        console.log("ComplianceRegistry :", address(compliance));
        console.log("ProofOfReserve     :", address(por));
        console.log("CircuitBreaker     :", address(breaker));
        console.log("SafetyVault        :", address(vault));
        console.log("ShieldRWAGuard     :", address(guard));
        console.log("Trusted Signer     :", trustedSigner);
        console.log("Max Risk Score     :", maxRiskScore);
    }
}