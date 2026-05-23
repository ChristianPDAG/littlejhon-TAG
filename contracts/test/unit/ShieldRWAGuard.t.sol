// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {ShieldRWAGuard} from "../../src/ShieldRWAGuard.sol";

contract ShieldRWAGuardTest is BaseTest {
    uint256 constant TRANSFER_AMOUNT = 1_000e18;
    uint256 constant NONCE = 1;
    uint256 constant DEADLINE = type(uint256).max;

    uint256 alicePk;
    address aliceSigner;

    function setUp() public override {
        super.setUp();

        // Create deterministic alice key for signing
        alicePk = 0xA11CE;
        aliceSigner = vm.addr(alicePk);

        // Re-verify alice as the deterministic address
        vm.prank(owner);
        compliance.revokeIdentity(alice);
        vm.prank(owner);
        compliance.verifyIdentity(aliceSigner, JURISDICTION_US, block.timestamp + IDENTITY_EXPIRY);

        // Fund aliceSigner
        vm.prank(owner);
        rwaToken.transfer(aliceSigner, 50_000e18);

        // Approve guard contract
        vm.prank(aliceSigner);
        rwaToken.approve(address(guard), type(uint256).max);
    }

    // ─── Helpers ────────────────────────────────────────────────────

    function _execute(uint256 amount, uint256 nonce, uint256 deadline, uint256 riskScore) internal {
        bytes memory userSig = _signTransfer(address(rwaToken), aliceSigner, bob, amount, nonce, deadline, alicePk);
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, amount, nonce, deadline, riskScore, trustedSignerPk
        );
        vm.prank(aliceSigner);
        guard.safeTransfer(address(rwaToken), aliceSigner, bob, amount, nonce, deadline, riskScore, userSig, attSig);
    }

    // ─── Safe Transfer Tests ────────────────────────────────────────

    function test_safeTransfer_success() public {
        _execute(TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE);
        assertEq(rwaToken.balanceOf(bob), 50_000e18 + TRANSFER_AMOUNT);
    }

    function test_safeTransfer_nonceConsumed() public {
        _execute(TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE);
        assertTrue(guard.usedNonces(aliceSigner, NONCE));
    }

    function test_revert_safeTransfer_nonceReused() public {
        _execute(TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE);

        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, trustedSignerPk
        );
        vm.prank(aliceSigner);
        vm.expectRevert(abi.encodeWithSelector(ShieldRWAGuard.NonceAlreadyUsed.selector, NONCE));
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    function test_revert_safeTransfer_invalidUserSignature() public {
        // Sign user portion with the wrong key
        uint256 wrongPk = 0xBAD;
        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, wrongPk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(
            abi.encodeWithSelector(ShieldRWAGuard.InvalidSignature.selector, vm.addr(wrongPk), aliceSigner)
        );
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    function test_revert_safeTransfer_invalidAttestationSignature() public {
        uint256 fakeBackendPk = 0xFEED;
        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, fakeBackendPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(
            abi.encodeWithSelector(
                ShieldRWAGuard.InvalidAttestation.selector, vm.addr(fakeBackendPk), trustedSigner
            )
        );
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    function test_revert_safeTransfer_attestationCoversDifferentAmount() public {
        // Attestation signed for amount X, but caller submits amount Y → digest mismatch → revert
        uint256 attestedAmount = TRANSFER_AMOUNT;
        uint256 submittedAmount = TRANSFER_AMOUNT + 1;

        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, submittedAmount, NONCE, DEADLINE, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, attestedAmount, NONCE, DEADLINE, DEFAULT_RISK_SCORE, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(); // recovered signer won't match trustedSigner
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, submittedAmount, NONCE, DEADLINE, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    function test_revert_safeTransfer_riskScoreAboveCap() public {
        uint256 highScore = MAX_RISK_SCORE + 1;
        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, highScore, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(
            abi.encodeWithSelector(ShieldRWAGuard.RiskScoreTooHigh.selector, highScore, MAX_RISK_SCORE)
        );
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, highScore, userSig, attSig
        );
    }

    function test_revert_safeTransfer_riskScoreOutOfRange() public {
        uint256 invalidScore = 101;
        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, invalidScore, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(abi.encodeWithSelector(ShieldRWAGuard.RiskScoreOutOfRange.selector, invalidScore));
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, invalidScore, userSig, attSig
        );
    }

    function test_revert_safeTransfer_tokenNotWhitelisted() public {
        address fakeToken = address(0xdead);
        bytes memory userSig =
            _signTransfer(fakeToken, aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, alicePk);
        bytes memory attSig = _signAttestation(
            fakeToken, aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(abi.encodeWithSelector(ShieldRWAGuard.TokenNotWhitelisted.selector, fakeToken));
        guard.safeTransfer(
            fakeToken, aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    function test_revert_safeTransfer_circuitBreaker() public {
        vm.prank(owner);
        breaker.triggerBreaker(address(rwaToken), "Emergency");

        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert();
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    function test_revert_safeTransfer_exceedsLimit() public {
        uint256 overLimit = TRANSFER_LIMIT + 1;
        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, overLimit, NONCE, DEADLINE, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, overLimit, NONCE, DEADLINE, DEFAULT_RISK_SCORE, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(
            abi.encodeWithSelector(ShieldRWAGuard.TransferExceedsLimit.selector, TRANSFER_LIMIT, overLimit)
        );
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, overLimit, NONCE, DEADLINE, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    function test_revert_safeTransfer_expiredDeadline() public {
        // Anchor the timeline explicitly so this test is independent of any default block.timestamp.
        vm.warp(1_000);
        uint256 deadline = 999; // strictly in the past

        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, deadline, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, deadline, DEFAULT_RISK_SCORE, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert();
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, deadline, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    // ─── View Simulation Tests ──────────────────────────────────────

    function test_canSafeTransfer_returnsTrue() public view {
        (bool can, string memory reason) =
            guard.canSafeTransfer(address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, DEFAULT_RISK_SCORE);
        assertTrue(can);
        assertEq(reason, "All checks passed");
    }

    function test_canSafeTransfer_unverifiedSender() public view {
        (bool can, string memory reason) =
            guard.canSafeTransfer(address(rwaToken), unauthorized, bob, TRANSFER_AMOUNT, DEFAULT_RISK_SCORE);
        assertFalse(can);
        assertEq(reason, "Sender not verified");
    }

    function test_canSafeTransfer_riskScoreExceedsCap() public view {
        (bool can, string memory reason) =
            guard.canSafeTransfer(address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, MAX_RISK_SCORE + 1);
        assertFalse(can);
        assertEq(reason, "Risk score exceeds cap");
    }

    // ─── Admin Tests ────────────────────────────────────────────────

    function test_whitelistToken() public {
        address newToken = address(0x1234);
        vm.prank(owner);
        guard.whitelistToken(newToken, 50_000e18);
        (bool whitelisted, uint256 limit) = guard.tokenConfigs(newToken);
        assertTrue(whitelisted);
        assertEq(limit, 50_000e18);
    }

    function test_delistToken() public {
        vm.prank(owner);
        guard.delistToken(address(rwaToken));
        (bool whitelisted,) = guard.tokenConfigs(address(rwaToken));
        assertFalse(whitelisted);
    }

    function test_setTrustedSigner_rotatesAndOldSignerStopsWorking() public {
        uint256 newPk = 0xC0FFEE;
        address newSigner = vm.addr(newPk);

        vm.prank(owner);
        guard.setTrustedSigner(newSigner);
        assertEq(guard.trustedSigner(), newSigner);

        // Old signer is no longer accepted.
        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, alicePk
        );
        bytes memory oldAttSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, trustedSignerPk
        );
        vm.prank(aliceSigner);
        vm.expectRevert(abi.encodeWithSelector(ShieldRWAGuard.InvalidAttestation.selector, trustedSigner, newSigner));
        guard.safeTransfer(
            address(rwaToken),
            aliceSigner,
            bob,
            TRANSFER_AMOUNT,
            NONCE,
            DEADLINE,
            DEFAULT_RISK_SCORE,
            userSig,
            oldAttSig
        );

        // New signer's attestation is accepted.
        bytes memory newAttSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, TRANSFER_AMOUNT, NONCE, DEADLINE, DEFAULT_RISK_SCORE, newPk
        );
        vm.prank(aliceSigner);
        guard.safeTransfer(
            address(rwaToken),
            aliceSigner,
            bob,
            TRANSFER_AMOUNT,
            NONCE,
            DEADLINE,
            DEFAULT_RISK_SCORE,
            userSig,
            newAttSig
        );
        assertEq(rwaToken.balanceOf(bob), 50_000e18 + TRANSFER_AMOUNT);
    }

    function test_revert_setTrustedSigner_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        guard.setTrustedSigner(address(0));
    }

    function test_revert_setTrustedSigner_unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        guard.setTrustedSigner(address(0x1234));
    }

    function test_setMaxRiskScore() public {
        vm.prank(owner);
        guard.setMaxRiskScore(50);
        assertEq(guard.maxRiskScore(), 50);
    }

    function test_revert_setMaxRiskScore_above100() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ShieldRWAGuard.MaxRiskScoreOutOfRange.selector, uint256(101)));
        guard.setMaxRiskScore(101);
    }

    // ─── Constructor Sanity ─────────────────────────────────────────

    function test_revert_constructor_zeroTrustedSigner() public {
        vm.expectRevert();
        new ShieldRWAGuard(
            owner, address(compliance), address(por), address(breaker), address(0), MAX_RISK_SCORE
        );
    }

    function test_revert_constructor_maxRiskScoreAbove100() public {
        vm.expectRevert(abi.encodeWithSelector(ShieldRWAGuard.MaxRiskScoreOutOfRange.selector, uint256(101)));
        new ShieldRWAGuard(owner, address(compliance), address(por), address(breaker), trustedSigner, 101);
    }
}
