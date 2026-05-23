// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {SafetyVault} from "../../src/core/SafetyVault.sol";
import {ICircuitBreaker} from "../../src/interfaces/ICircuitBreaker.sol";
import {IComplianceRegistry} from "../../src/interfaces/IComplianceRegistry.sol";

contract SafetyVaultTest is BaseTest {
    uint256 constant DEPOSIT_AMOUNT = 10_000e18;

    function setUp() public override {
        super.setUp();
        // Alice approves vault
        vm.prank(alice);
        rwaToken.approve(address(vault), type(uint256).max);
    }

    // ─── Deposit Tests ──────────────────────────────────────────────

    function test_deposit_success() public {
        vm.prank(alice);
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);
        assertEq(vault.balances(address(rwaToken), alice), DEPOSIT_AMOUNT);
    }

    function test_deposit_incrementsTotalDeposited() public {
        vm.prank(alice);
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);
        (,, uint256 totalDeposited) = vault.tokens(address(rwaToken));
        assertEq(totalDeposited, DEPOSIT_AMOUNT);
    }

    function test_revert_deposit_notAllowed() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafetyVault.TokenNotAllowed.selector, address(0xdead)));
        vault.deposit(address(0xdead), DEPOSIT_AMOUNT);
    }

    function test_revert_deposit_notVerified() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IComplianceRegistry.IdentityNotVerified.selector, unauthorized));
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);
    }

    function test_revert_deposit_circuitBreakerHalted() public {
        vm.prank(owner);
        breaker.triggerBreaker(address(rwaToken), "Emergency");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.BreakerIsTriggered.selector, address(rwaToken)));
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);
    }

    // ─── Withdraw Tests ─────────────────────────────────────────────

    function test_withdraw_success() public {
        vm.prank(alice);
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);

        vm.prank(alice);
        vault.withdraw(address(rwaToken), DEPOSIT_AMOUNT);
        assertEq(vault.balances(address(rwaToken), alice), 0);
    }

    function test_revert_withdraw_insufficientBalance() public {
        vm.prank(alice);
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafetyVault.WithdrawalExceedsBalance.selector, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT + 1));
        vault.withdraw(address(rwaToken), DEPOSIT_AMOUNT + 1);
    }

    function test_revert_withdraw_circuitBreaker() public {
        vm.prank(alice);
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);

        vm.prank(owner);
        breaker.triggerBreaker(address(rwaToken), "Emergency");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.BreakerIsTriggered.selector, address(rwaToken)));
        vault.withdraw(address(rwaToken), DEPOSIT_AMOUNT);
    }

    // ─── Emergency Drain ────────────────────────────────────────────

    function test_emergencyDrain_movesFullBalance() public {
        vm.prank(alice);
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);

        vm.prank(owner);
        breaker.triggerBreaker(address(rwaToken), "Emergency");

        uint256 vaultBal = rwaToken.balanceOf(address(vault));
        uint256 ownerBefore = rwaToken.balanceOf(owner);

        vm.prank(owner);
        vault.emergencyDrain(address(rwaToken), owner);

        assertEq(rwaToken.balanceOf(address(vault)), 0);
        assertEq(rwaToken.balanceOf(owner) - ownerBefore, vaultBal);
        assertTrue(vault.emergencyDrained(address(rwaToken)));
    }

    function test_revert_emergencyDrain_notInEmergency() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SafetyVault.NotInEmergency.selector, address(rwaToken)));
        vault.emergencyDrain(address(rwaToken), owner);
    }

    function test_revert_emergencyDrain_alreadyDrained() public {
        vm.prank(owner);
        breaker.triggerBreaker(address(rwaToken), "Emergency");

        vm.prank(owner);
        vault.emergencyDrain(address(rwaToken), owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SafetyVault.TokenAlreadyDrained.selector, address(rwaToken)));
        vault.emergencyDrain(address(rwaToken), owner);
    }

    function test_revert_deposit_afterDrain() public {
        vm.prank(owner);
        breaker.triggerBreaker(address(rwaToken), "Emergency");
        vm.prank(owner);
        vault.emergencyDrain(address(rwaToken), owner);

        // Resolve breaker so the deposit() path reaches the drained check.
        vm.prank(owner);
        breaker.resolveBreaker(address(rwaToken));
        vm.prank(owner);
        breaker.resetBreaker(address(rwaToken));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafetyVault.TokenAlreadyDrained.selector, address(rwaToken)));
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);
    }

    // ─── Rescue Excess Tokens ───────────────────────────────────────

    function test_rescueExcessTokens_onlyExcess() public {
        vm.prank(alice);
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);

        // Simulate accidental direct transfer to the vault.
        uint256 stray = 1_234e18;
        vm.prank(bob);
        rwaToken.transfer(address(vault), stray);

        uint256 ownerBefore = rwaToken.balanceOf(owner);
        vm.prank(owner);
        vault.rescueExcessTokens(address(rwaToken), owner, stray);

        assertEq(rwaToken.balanceOf(owner) - ownerBefore, stray);
        // User balance unaffected.
        assertEq(vault.balances(address(rwaToken), alice), DEPOSIT_AMOUNT);
    }

    function test_revert_rescueExcessTokens_exceedsExcess() public {
        vm.prank(alice);
        vault.deposit(address(rwaToken), DEPOSIT_AMOUNT);

        // No stray funds → excess is 0, any request reverts.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SafetyVault.NoExcessAvailable.selector, address(rwaToken), 1, 0));
        vault.rescueExcessTokens(address(rwaToken), owner, 1);
    }
}