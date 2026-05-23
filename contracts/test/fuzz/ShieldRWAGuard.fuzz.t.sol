// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {ShieldRWAGuard} from "../../src/ShieldRWAGuard.sol";

/// @title ShieldRWAGuardFuzzTest — Property-based tests on safeTransfer's signature & risk gates
contract ShieldRWAGuardFuzzTest is BaseTest {
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
        rwaToken.transfer(aliceSigner, 1_000_000e18);

        vm.prank(aliceSigner);
        rwaToken.approve(address(guard), type(uint256).max);
    }

    /// @dev For any (amount, nonce, riskScore) within bounds, a correctly-signed transfer succeeds
    ///      and exactly `amount` lands at the recipient.
    function testFuzz_safeTransfer_validBundle(uint128 amount, uint64 nonce, uint8 riskScore) public {
        // Bound: non-zero, within per-tx limit, within risk cap.
        amount = uint128(bound(uint256(amount), 1, TRANSFER_LIMIT));
        riskScore = uint8(bound(uint256(riskScore), 0, MAX_RISK_SCORE));

        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, amount, nonce, type(uint256).max, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, amount, nonce, type(uint256).max, riskScore, trustedSignerPk
        );

        uint256 bobBefore = rwaToken.balanceOf(bob);
        vm.prank(aliceSigner);
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, amount, nonce, type(uint256).max, riskScore, userSig, attSig
        );

        assertEq(rwaToken.balanceOf(bob) - bobBefore, amount);
        assertTrue(guard.usedNonces(aliceSigner, nonce));
    }

    /// @dev Any riskScore strictly above the cap (but ≤ 100) must revert with RiskScoreTooHigh.
    function testFuzz_safeTransfer_rejectsRiskAboveCap(uint8 riskScore) public {
        riskScore = uint8(bound(uint256(riskScore), MAX_RISK_SCORE + 1, 100));

        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, riskScore, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(
            abi.encodeWithSelector(ShieldRWAGuard.RiskScoreTooHigh.selector, riskScore, MAX_RISK_SCORE)
        );
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, riskScore, userSig, attSig
        );
    }

    /// @dev Any riskScore > 100 must revert with RiskScoreOutOfRange (regardless of cap).
    function testFuzz_safeTransfer_rejectsRiskOutOfRange(uint256 riskScore) public {
        riskScore = bound(riskScore, 101, type(uint256).max);

        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, riskScore, trustedSignerPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(abi.encodeWithSelector(ShieldRWAGuard.RiskScoreOutOfRange.selector, riskScore));
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, riskScore, userSig, attSig
        );
    }

    /// @dev Any attestation signed by a key OTHER than the trusted signer must be rejected.
    ///      Bound the fuzzed PK to secp256k1's valid range to avoid vm.sign reverts.
    function testFuzz_safeTransfer_rejectsForeignAttestation(uint256 wrongPk) public {
        // secp256k1 curve order minus one
        uint256 maxPk = 115792089237316195423570985008687907852837564279074904382605163141518161494336;
        wrongPk = bound(wrongPk, 1, maxPk);
        // Exclude the legitimate trustedSignerPk to guarantee a mismatch.
        if (wrongPk == trustedSignerPk) wrongPk = trustedSignerPk + 1;
        address wrongSigner = vm.addr(wrongPk);

        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, DEFAULT_RISK_SCORE, wrongPk
        );

        vm.prank(aliceSigner);
        vm.expectRevert(
            abi.encodeWithSelector(ShieldRWAGuard.InvalidAttestation.selector, wrongSigner, trustedSigner)
        );
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, 1, type(uint256).max, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }

    /// @dev A correctly-signed but already-consumed nonce must always revert with NonceAlreadyUsed.
    function testFuzz_safeTransfer_replayRejected(uint64 nonce) public {
        bytes memory userSig = _signTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, nonce, type(uint256).max, alicePk
        );
        bytes memory attSig = _signAttestation(
            address(rwaToken), aliceSigner, bob, 1e18, nonce, type(uint256).max, DEFAULT_RISK_SCORE, trustedSignerPk
        );

        vm.prank(aliceSigner);
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, nonce, type(uint256).max, DEFAULT_RISK_SCORE, userSig, attSig
        );

        vm.prank(aliceSigner);
        vm.expectRevert(abi.encodeWithSelector(ShieldRWAGuard.NonceAlreadyUsed.selector, uint256(nonce)));
        guard.safeTransfer(
            address(rwaToken), aliceSigner, bob, 1e18, nonce, type(uint256).max, DEFAULT_RISK_SCORE, userSig, attSig
        );
    }
}
