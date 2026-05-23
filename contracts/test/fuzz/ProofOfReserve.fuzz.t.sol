// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {IProofOfReserve} from "../../src/interfaces/IProofOfReserve.sol";

/// @title ProofOfReserveFuzzTest — Property tests on reserve verification + staleness handling
contract ProofOfReserveFuzzTest is BaseTest {
    /// @dev verifyReserve returns true iff reserves ≥ totalSupply, never reverts on positives.
    function testFuzz_verifyReserve_matchesReserveVsSupply(uint128 reserve) public {
        porOracle.setPrice(int256(uint256(reserve)));

        bool backed = por.verifyReserve(address(rwaToken));
        assertEq(backed, uint256(reserve) >= rwaToken.totalSupply());
    }

    /// @dev A negative reserve balance is treated as undercollateralized — must revert,
    ///      never silently pass via int→uint wraparound (the bug fixed in Fase A2).
    function testFuzz_verifyReserve_negativeReserveReverts(int128 negReserve) public {
        vm.assume(negReserve < 0);
        porOracle.setPrice(int256(negReserve));

        vm.expectRevert(abi.encodeWithSelector(IProofOfReserve.ReserveUndercollateralized.selector, address(rwaToken), 0));
        por.verifyReserve(address(rwaToken));
    }

    /// @dev Any updatedAt strictly greater than block.timestamp must be treated as stale.
    function testFuzz_verifyReserve_futureTimestampReverts(uint256 future) public {
        future = bound(future, block.timestamp + 1, type(uint64).max);
        porOracle.setRound(int256(INITIAL_RESERVES), future);

        vm.expectRevert(abi.encodeWithSelector(IProofOfReserve.StaleData.selector, address(rwaToken), 0));
        por.verifyReserve(address(rwaToken));
    }

    /// @dev Any age > maxStaleness must revert with StaleData carrying the actual age.
    function testFuzz_verifyReserve_oldTimestampReverts(uint256 ageBeyondCap) public {
        uint256 maxStaleness = 1 hours;
        uint256 anchor = 365 days; // give us plenty of room for arbitrary old updates
        // ageBeyondCap must keep oldUpdate ≥ 1, so cap it at (anchor - maxStaleness - 1).
        ageBeyondCap = bound(ageBeyondCap, 1, anchor - maxStaleness - 1);

        vm.warp(anchor);
        uint256 oldUpdate = anchor - maxStaleness - ageBeyondCap;
        porOracle.setRound(int256(INITIAL_RESERVES), oldUpdate);

        vm.expectRevert(
            abi.encodeWithSelector(IProofOfReserve.StaleData.selector, address(rwaToken), maxStaleness + ageBeyondCap)
        );
        por.verifyReserve(address(rwaToken));
    }
}
