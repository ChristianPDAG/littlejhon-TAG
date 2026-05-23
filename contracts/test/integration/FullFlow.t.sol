// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {ShieldRWAGuard} from "../../src/ShieldRWAGuard.sol";
import {ICircuitBreaker} from "../../src/interfaces/ICircuitBreaker.sol";
import {IComplianceRegistry} from "../../src/interfaces/IComplianceRegistry.sol";
import {IProofOfReserve} from "../../src/interfaces/IProofOfReserve.sol";

/// @title FullFlowTest — End-to-end integration test for the Safety Layer
contract FullFlowTest is BaseTest {
    uint256 alicePk;
    address aliceSigner;

    function setUp() public override {
        super.setUp();

        alicePk = 0xA11CE;
        aliceSigner = vm.addr(alicePk);

        vm.prank(owner);
        compliance.revokeIdentity(alice);
        vm.prank(owner);
        compliance.verifyIdentity(aliceSigner, JURISDICTION_US, block.timestamp + IDENTITY_EXPIRY);

        vm.prank(owner);
        rwaToken.transfer(aliceSigner, 50_000e18);

        vm.prank(aliceSigner);
        rwaToken.approve(address(guard), type(uint256).max);
        vm.prank(aliceSigner);
        rwaToken.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════
    // HAPPY PATH: Full safe transfer flow
    // ═══════════════════════════════════════════════════════════════

    function test_fullHappyPath_safeTransfer() public {
        uint256 amount = 5_000e18;
        uint256 deadline = type(uint256).max;
        bytes memory userSig = _signTransfer(address(rwaToken), aliceSigner, bob, amount, 1, deadline, alicePk);
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, amount, 1, deadline, DEFAULT_RISK_SCORE, trustedSignerPk
        );

        uint256 bobBefore = rwaToken.balanceOf(bob);

        vm.prank(aliceSigner);
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, amount, 1, deadline, DEFAULT_RISK_SCORE, userSig, attSig
        );

        assertEq(rwaToken.balanceOf(bob) - bobBefore, amount);
    }

    // ═══════════════════════════════════════════════════════════════
    // HAPPY PATH: Full vault deposit → withdraw flow
    // ═══════════════════════════════════════════════════════════════

    function test_fullHappyPath_vaultDepositWithdraw() public {
        uint256 amount = 10_000e18;

        // Deposit
        vm.prank(aliceSigner);
        vault.deposit(address(rwaToken), amount);
        assertEq(vault.balances(address(rwaToken), aliceSigner), amount);

        // Withdraw
        vm.prank(aliceSigner);
        vault.withdraw(address(rwaToken), amount);
        assertEq(vault.balances(address(rwaToken), aliceSigner), 0);
    }

    // ═══════════════════════════════════════════════════════════════
    // SECURITY: Circuit breaker blocks all operations
    // ═══════════════════════════════════════════════════════════════

    function test_security_circuitBreaker_blocksEverything() public {
        // Price drops 20%
        priceOracle.setPrice(int256(INITIAL_PRICE * 80 / 100));
        breaker.autoTriggerIfNeeded(address(rwaToken));
        assertTrue(breaker.isHalted(address(rwaToken)));

        // Vault deposit blocked
        vm.prank(aliceSigner);
        vm.expectRevert();
        vault.deposit(address(rwaToken), 1_000e18);

        // Vault withdraw blocked
        vm.prank(aliceSigner);
        vm.expectRevert();
        vault.withdraw(address(rwaToken), 1_000e18);

        // Safe transfer blocked
        uint256 deadline = type(uint256).max;
        bytes memory userSig = _signTransfer(address(rwaToken), aliceSigner, bob, 1_000e18, 1, deadline, alicePk);
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, 1_000e18, 1, deadline, DEFAULT_RISK_SCORE, trustedSignerPk
        );
        vm.prank(aliceSigner);
        vm.expectRevert();
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, 1_000e18, 1, deadline, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    // ═══════════════════════════════════════════════════════════════
    // SECURITY: Unverified identity cannot interact
    // ═══════════════════════════════════════════════════════════════

    function test_security_unverifiedUser_blocked() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IComplianceRegistry.IdentityNotVerified.selector, unauthorized));
        vault.deposit(address(rwaToken), 1_000e18);
    }

    // ═══════════════════════════════════════════════════════════════
    // SECURITY: Expired identity blocked
    // ═══════════════════════════════════════════════════════════════

    function test_security_expiredIdentity_blocked() public {
        vm.warp(block.timestamp + IDENTITY_EXPIRY + 1);

        vm.prank(aliceSigner);
        vm.expectRevert(abi.encodeWithSelector(IComplianceRegistry.IdentityNotVerified.selector, aliceSigner));
        vault.deposit(address(rwaToken), 1_000e18);
    }

    // ═══════════════════════════════════════════════════════════════
    // SECURITY: Undercollateralized reserve blocks withdrawals
    // ═══════════════════════════════════════════════════════════════

    function test_security_undercollateralizedReserve() public {
        // Deposit first
        vm.prank(aliceSigner);
        vault.deposit(address(rwaToken), 10_000e18);

        // Drop PoR below total supply
        porOracle.setPrice(int256(100)); // Almost zero reserves

        // Withdraw should fail due to PoR check
        vm.prank(aliceSigner);
        vm.expectRevert("SafetyVault: reserve verification failed");
        vault.withdraw(address(rwaToken), 10_000e18);
    }

    // ═══════════════════════════════════════════════════════════════
    // RECOVERY: Emergency drain during circuit breaker
    // ═══════════════════════════════════════════════════════════════

    function test_recovery_emergencyDrain() public {
        vm.prank(aliceSigner);
        vault.deposit(address(rwaToken), 10_000e18);

        // Trigger breaker
        vm.prank(owner);
        breaker.triggerBreaker(address(rwaToken), "Security incident");

        uint256 vaultBal = rwaToken.balanceOf(address(vault));
        uint256 ownerBefore = rwaToken.balanceOf(owner);

        // Owner drains the full vault balance to the rescue destination
        vm.prank(owner);
        vault.emergencyDrain(address(rwaToken), owner);

        assertEq(rwaToken.balanceOf(address(vault)), 0);
        assertEq(rwaToken.balanceOf(owner) - ownerBefore, vaultBal);
        assertTrue(vault.emergencyDrained(address(rwaToken)));

        // Post-drain, deposits and withdraws revert for that token
        vm.prank(aliceSigner);
        vm.expectRevert();
        vault.deposit(address(rwaToken), 1);
        vm.prank(aliceSigner);
        vm.expectRevert();
        vault.withdraw(address(rwaToken), 1);
    }

    // ═══════════════════════════════════════════════════════════════
    // GOVERNANCE: Timelock-controlled parameter change
    // ═══════════════════════════════════════════════════════════════

    function test_governance_timelockUpdateThreshold() public {
        // Transfer breaker ownership to timelock so it can execute governance actions
        vm.prank(owner);
        breaker.transferOwnership(address(timelock));

        uint256 newThreshold = 3000; // 30%
        bytes memory data = abi.encodeWithSignature("updateDeviationThreshold(uint256)", newThreshold);

        vm.prank(owner);
        timelock.schedule(address(breaker), data, 0);

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        vm.prank(owner);
        timelock.execute(address(breaker), data);
    }

    // ═══════════════════════════════════════════════════════════════
    // MULTIHOP: Multiple sequential safe transfers
    // ═══════════════════════════════════════════════════════════════

    function test_multihop_sequentialTransfers() public {
        uint256 deadline = type(uint256).max;
        for (uint256 i = 1; i <= 5; i++) {
            bytes memory userSig =
                _signTransfer(address(rwaToken), aliceSigner, bob, 1_000e18, i, deadline, alicePk);
            bytes memory attSig = _signAttestation(
                address(rwaToken), aliceSigner, bob, 1_000e18, i, deadline, DEFAULT_RISK_SCORE, trustedSignerPk
            );
            vm.prank(aliceSigner);
            guard.safeTransfer(
                address(rwaToken), aliceSigner, bob, 1_000e18, i, deadline, DEFAULT_RISK_SCORE, userSig, attSig
            );
        }

        assertEq(rwaToken.balanceOf(bob), 50_000e18 + 5_000e18);
    }
}