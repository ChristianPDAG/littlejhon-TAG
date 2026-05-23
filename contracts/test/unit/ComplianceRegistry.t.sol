// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ComplianceRegistry} from "../../src/core/ComplianceRegistry.sol";
import {IComplianceRegistry} from "../../src/interfaces/IComplianceRegistry.sol";
import {SafetyChecks} from "../../src/libraries/SafetyChecks.sol";

contract ComplianceRegistryTest is Test {
    ComplianceRegistry public registry;
    address public owner;
    address public alice;
    address public bob;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.prank(owner);
        registry = new ComplianceRegistry(owner);
    }

    // ─── Verification Tests ─────────────────────────────────────────

    function test_verifyIdentity() public {
        uint256 expiry = block.timestamp + 365 days;
        vm.prank(owner);
        registry.verifyIdentity(alice, 1, expiry);

        (uint256 jur, uint256 exp, bool active) = registry.getIdentity(alice);
        assertEq(jur, 1);
        assertEq(exp, expiry);
        assertTrue(active);
    }

    function test_isVerified_returnsTrue() public {
        vm.prank(owner);
        registry.verifyIdentity(alice, 1, block.timestamp + 365 days);
        assertTrue(registry.isVerified(alice));
    }

    function test_isVerified_returnsFalse_forUnverified() public view {
        assertFalse(registry.isVerified(alice));
    }

    function test_isVerified_returnsFalse_afterExpiry() public {
        uint256 expiry = block.timestamp + 100;
        vm.prank(owner);
        registry.verifyIdentity(alice, 1, expiry);

        vm.warp(block.timestamp + 101);
        assertFalse(registry.isVerified(alice));
    }

    // ─── Revoke Tests ───────────────────────────────────────────────

    function test_revokeIdentity() public {
        vm.prank(owner);
        registry.verifyIdentity(alice, 1, block.timestamp + 365 days);

        vm.prank(owner);
        registry.revokeIdentity(alice);
        assertFalse(registry.isVerified(alice));
    }

    // ─── Jurisdiction Tests ─────────────────────────────────────────

    function test_blockJurisdiction() public {
        vm.prank(owner);
        registry.blockJurisdiction(1);
        assertTrue(registry.isJurisdictionBlocked(1));
    }

    function test_unblockJurisdiction() public {
        vm.startPrank(owner);
        registry.blockJurisdiction(1);
        registry.unblockJurisdiction(1);
        vm.stopPrank();
        assertFalse(registry.isJurisdictionBlocked(1));
    }

    // ─── Access Control Tests ───────────────────────────────────────

    function test_revert_verifyIdentity_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        registry.verifyIdentity(bob, 1, block.timestamp + 365 days);
    }

    function test_revert_revokeIdentity_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        registry.revokeIdentity(bob);
    }

    // ─── Validation Tests ───────────────────────────────────────────

    function test_revert_verifyIdentity_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(SafetyChecks.ZeroAddress.selector);
        registry.verifyIdentity(address(0), 1, block.timestamp + 365 days);
    }

    function test_revert_verifyIdentity_pastExpiry() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SafetyChecks.InvalidExpiry.selector, 0, block.timestamp));
        registry.verifyIdentity(alice, 1, 0);
    }

    // ─── Event Tests ────────────────────────────────────────────────

    function test_emit_IdentityVerified() public {
        uint256 expiry = block.timestamp + 365 days;
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IComplianceRegistry.IdentityVerified(alice, 1, expiry);
        registry.verifyIdentity(alice, 1, expiry);
    }

    function test_emit_IdentityRevoked() public {
        vm.prank(owner);
        registry.verifyIdentity(alice, 1, block.timestamp + 365 days);

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IComplianceRegistry.IdentityRevoked(alice);
        registry.revokeIdentity(alice);
    }
}