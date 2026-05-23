// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {CircuitBreaker} from "../../src/core/CircuitBreaker.sol";
import {ICircuitBreaker} from "../../src/interfaces/ICircuitBreaker.sol";

/// @title CircuitBreakerFuzzTest — Property tests on price-deviation math + auto-trigger semantics
contract CircuitBreakerFuzzTest is BaseTest {
    /// @dev For any current price, the reported deviationBps matches the formula:
    ///      |current - reference| * 10_000 / reference, never overflows, never reverts on positives.
    function testFuzz_checkPriceDeviation_matchesFormula(uint256 newPrice) public {
        // Bound to a sane positive int256 range to avoid setPrice overflow.
        newPrice = bound(newPrice, 1, uint256(type(int256).max) / 10_000);

        priceOracle.setPrice(int256(newPrice));
        uint256 deviation = breaker.checkPriceDeviation(address(rwaToken));

        uint256 ref = INITIAL_PRICE;
        uint256 expected = newPrice > ref ? ((newPrice - ref) * 10_000) / ref : ((ref - newPrice) * 10_000) / ref;
        assertEq(deviation, expected, "deviationBps formula mismatch");
    }

    /// @dev If the deviation exceeds the threshold, autoTriggerIfNeeded MUST trip the breaker.
    function testFuzz_autoTrigger_trigersWhenAboveThreshold(uint256 newPrice) public {
        // Force at least a 16% drop (above the default 15% threshold).
        newPrice = bound(newPrice, 1, (INITIAL_PRICE * 84) / 100);
        priceOracle.setPrice(int256(newPrice));

        bool triggered = breaker.autoTriggerIfNeeded(address(rwaToken));
        assertTrue(triggered, "should have triggered");
        assertTrue(breaker.isHalted(address(rwaToken)));
    }

    /// @dev Deviations strictly below the threshold MUST NOT trigger the breaker.
    function testFuzz_autoTrigger_silentBelowThreshold(uint256 newPrice) public {
        // 1% to 14% deviation in either direction — well below the 15% default.
        uint256 maxDeltaBps = 1400;
        uint256 maxDelta = (INITIAL_PRICE * maxDeltaBps) / 10_000;
        newPrice = bound(newPrice, INITIAL_PRICE - maxDelta, INITIAL_PRICE + maxDelta);
        priceOracle.setPrice(int256(newPrice));

        bool triggered = breaker.autoTriggerIfNeeded(address(rwaToken));
        assertFalse(triggered, "should not have triggered");
        assertFalse(breaker.isHalted(address(rwaToken)));
    }
}
