// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SafetyChecks — Reusable validation library for the Safety Layer
/// @notice Centralized require/error logic to keep contracts DRY and auditable
library SafetyChecks {
    // ─── Custom Errors ──────────────────────────────────────────────
    error ZeroAddress();
    error ZeroAmount();
    error ExpiredDeadline(uint256 deadline, uint256 currentTime);
    error InsufficientBalance(uint256 available, uint256 required);
    error InvalidExpiry(uint256 expiry, uint256 currentTime);
    error InvalidThreshold(uint256 threshold);

    /// @dev EIP-712 domain separator components
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal constant TRANSFER_TYPEHASH =
        keccak256("ShieldTransfer(address token,address from,address to,uint256 amount,uint256 nonce,uint256 deadline)");

    bytes32 internal constant RISK_ATTESTATION_TYPEHASH = keccak256(
        "RiskAttestation(address token,address from,address to,uint256 amount,uint256 nonce,uint256 deadline,uint256 riskScore)"
    );

    /// @notice Validate that an address is not zero
    function requireNonZero(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    /// @notice Validate that an amount is not zero
    function requireNonZero(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /// @notice Validate a deadline has not passed
    function requireNotExpired(uint256 deadline) internal view {
        if (block.timestamp > deadline) revert ExpiredDeadline(deadline, block.timestamp);
    }

    /// @notice Validate an identity expiry is in the future
    function requireValidExpiry(uint256 expiry) internal view {
        if (expiry <= block.timestamp) revert InvalidExpiry(expiry, block.timestamp);
    }

    /// @notice Validate a threshold is within acceptable bounds (1% - 50%)
    function requireValidThreshold(uint256 thresholdBps) internal pure {
        if (thresholdBps < 100 || thresholdBps > 5000) revert InvalidThreshold(thresholdBps);
    }

    /// @notice Compute EIP-712 domain separator
    function computeDomainSeparator(string memory name, string memory version, address contractAddr)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                contractAddr
            )
        );
    }

    /// @notice Compute EIP-712 typed struct hash for ShieldTransfer
    function computeTransferStructHash(address token, address from, address to, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(TRANSFER_TYPEHASH, token, from, to, amount, nonce, deadline));
    }

    /// @notice Compute EIP-712 typed struct hash for RiskAttestation
    /// @dev Shares the same nonce/deadline as the user's ShieldTransfer — the attestation endorses
    ///      the exact transfer the user signed, plus a riskScore the contract enforces against a cap.
    function computeAttestationStructHash(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 riskScore
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(RISK_ATTESTATION_TYPEHASH, token, from, to, amount, nonce, deadline, riskScore)
        );
    }

    /// @notice Recover signer from EIP-712 signature
    function recoverSigner(
        bytes32 domainSeparator,
        bytes32 structHash,
        bytes memory signature
    ) internal pure returns (address) {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (bytes32 r, bytes32 s, uint8 v) = parseSignature(signature);
        return ecrecover(digest, v, r, s);
    }

    /// @notice Parse a 65-byte signature into (r, s, v) components
    function parseSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "SafetyChecks: invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}