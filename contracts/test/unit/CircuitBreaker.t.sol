// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CircuitBreaker} from "../../src/core/CircuitBreaker.sol";
import {ICircuitBreaker} from "../../src/interfaces/ICircuitBreaker.sol";
import {MockOracle} from "../../src/mocks/MockOracle.sol";

contract CircuitBreakerTest is Test {
    CircuitBreaker public breaker;
    MockOracle public oracle;
    address public owner;
    address public token;

    uint256 constant INITIAL_PRICE = 150_000_000_000; // $150

    function setUp() public {
        owner = makeAddr("owner");
        token = makeAddr("TSLA");
        oracle = new MockOracle(8, "TSLA/USD");
        oracle.setPrice(int256(INITIAL_PRICE));

        vm.prank(owner);
        breaker = new CircuitBreaker(owner);

        vm.prank(owner);
        breaker.registerToken(token, address(oracle));
    }

    // ─── State Tests ────────────────────────────────────────────────

    function test_initialState_isActive() public view {
        assertEq(uint256(breaker.getState(token)), uint256(ICircuitBreaker.BreakerState.ACTIVE));
    }

    function test_isHalted_initiallyFalse() public view {
        assertFalse(breaker.isHalted(token));
    }

    // ─── Manual Trigger Tests ───────────────────────────────────────

    function test_triggerBreaker_manually() public {
        vm.prank(owner);
        breaker.triggerBreaker(token, "Manual: suspicious activity");
        assertTrue(breaker.isHalted(token));
        assertEq(uint256(breaker.getState(token)), uint256(ICircuitBreaker.BreakerState.TRIGGERED));
    }

    function test_resolveBreaker() public {
        vm.prank(owner);
        breaker.triggerBreaker(token, "Manual");

        vm.prank(owner);
        breaker.resolveBreaker(token);
        assertEq(uint256(breaker.getState(token)), uint256(ICircuitBreaker.BreakerState.RESOLVED));
    }

    function test_resetBreaker() public {
        vm.startPrank(owner);
        breaker.triggerBreaker(token, "Manual");
        breaker.resolveBreaker(token);
        breaker.resetBreaker(token);
        vm.stopPrank();
        assertEq(uint256(breaker.getState(token)), uint256(ICircuitBreaker.BreakerState.ACTIVE));
    }

    function test_revert_trigger_alreadyTriggered() public {
        vm.startPrank(owner);
        breaker.triggerBreaker(token, "Manual");
        vm.expectRevert(
            abi.encodeWithSelector(
                ICircuitBreaker.InvalidStateTransition.selector,
                ICircuitBreaker.BreakerState.TRIGGERED,
                ICircuitBreaker.BreakerState.TRIGGERED
            )
        );
        breaker.triggerBreaker(token, "Again");
        vm.stopPrank();
    }

    // ─── Auto Trigger Tests ─────────────────────────────────────────

    function test_autoTrigger_onPriceDeviation() public {
        // Drop price by 20% (threshold is 15%)
        oracle.setPrice(int256(INITIAL_PRICE * 80 / 100));
        bool triggered = breaker.autoTriggerIfNeeded(token);
        assertTrue(triggered);
        assertTrue(breaker.isHalted(token));
    }

    function test_noAutoTrigger_belowThreshold() public {
        // Price drops only 10% (threshold is 15%)
        oracle.setPrice(int256(INITIAL_PRICE * 90 / 100));
        bool triggered = breaker.autoTriggerIfNeeded(token);
        assertFalse(triggered);
    }

    // ─── Deviation Check ────────────────────────────────────────────

    function test_checkPriceDeviation_noChange() public view {
        uint256 deviation = breaker.checkPriceDeviation(token);
        assertEq(deviation, 0);
    }

    function test_checkPriceDeviation_20percent() public {
        oracle.setPrice(int256(INITIAL_PRICE * 80 / 100));
        uint256 deviation = breaker.checkPriceDeviation(token);
        assertEq(deviation, 2000); // 20%
    }

    // ─── Access Control ─────────────────────────────────────────────

    function test_revert_trigger_unauthorized() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", makeAddr("attacker")));
        breaker.triggerBreaker(token, "Hack");
    }

    // ─── Threshold Update ───────────────────────────────────────────

    function test_updateDeviationThreshold() public {
        vm.prank(owner);
        breaker.updateDeviationThreshold(2000); // 20%
        // Now 15% drop should NOT trigger
        oracle.setPrice(int256(INITIAL_PRICE * 85 / 100));
        bool triggered = breaker.autoTriggerIfNeeded(token);
        assertFalse(triggered);
    }
}