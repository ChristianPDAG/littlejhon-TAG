"use client";

import { Send, ShieldAlert } from "lucide-react";
import { useMemo, useState } from "react";
import { useAccount, usePublicClient, useSignTypedData, useWriteContract } from "wagmi";
import type { Address } from "viem";
import { getPublicEnv } from "@/config/env";
import { erc20Abi, shieldRwaGuardAbi, shieldTransferTypes } from "@/lib/contracts/abis";
import type { AttestResponse, RiskCheckRequest, RiskCheckResponse } from "@/lib/types";

function explainContractError(cause: unknown) {
  const message = cause instanceof Error ? cause.message : String(cause);
  const translations: [string, string][] = [
    ["TokenNotWhitelisted", "Token is not whitelisted in ShieldRWAGuard."],
    ["NonceAlreadyUsed", "This nonce was already consumed. Request a fresh attestation."],
    ["RiskScoreTooHigh", "Backend risk score is above the on-chain max risk cap."],
    ["RiskScoreOutOfRange", "Backend risk score is outside the contract scale."],
    ["InvalidSignature", "Wallet signature does not match the transfer sender."],
    ["InvalidAttestation", "Backend attestation signer does not match ShieldRWAGuard.trustedSigner."],
    ["IdentityNotVerified", "Sender or recipient is not verified in ComplianceRegistry."],
    ["BreakerIsTriggered", "CircuitBreaker is halted for this token."],
    ["TransferExceedsLimit", "Amount exceeds the token transfer limit."],
    ["reserve verification failed", "Proof of Reserve verification failed."],
    ["allowance", "Token allowance is insufficient for ShieldRWAGuard."],
  ];
  return translations.find(([needle]) => message.includes(needle))?.[1] ?? message;
}

export function ExecutionPanel({
  executionEnabled,
  healthStatus,
  request,
  result,
  onTransaction,
}: {
  executionEnabled: boolean | null;
  healthStatus: "loading" | "ready" | "error";
  request: RiskCheckRequest | null;
  result: RiskCheckResponse | null;
  onTransaction: (txHash: string) => void;
}) {
  const env = getPublicEnv();
  const { address, chain } = useAccount();
  const publicClient = usePublicClient();
  const { signTypedDataAsync } = useSignTypedData();
  const { writeContractAsync } = useWriteContract();
  const [confirmed, setConfirmed] = useState(false);
  const [status, setStatus] = useState<string>("");
  const [error, setError] = useState<string>("");

  const canAttempt = useMemo(() => {
    if (!request || !result || !address || result.decision === "BLOCK") return false;
    if (executionEnabled !== true) return false;
    if (chain?.id !== request.chainId) return false;
    if (request.from.toLowerCase() !== address.toLowerCase()) return false;
    if (!result.onchainPreview?.canTransfer) return false;
    if (result.decision !== "ALLOW" && !confirmed) return false;
    return true;
  }, [address, chain?.id, confirmed, executionEnabled, request, result]);

  async function execute() {
    if (!request || !result || !address || !chain || !publicClient) return;

    setError("");
    setStatus("Checking token allowance");

    try {
      const token = request.token ?? result.onchainPreview?.token;
      if (!token) throw new Error("No executable token configured for this scenario.");
      const amount = BigInt(request.amount);
      const allowance = await publicClient.readContract({
        address: token,
        abi: erc20Abi,
        functionName: "allowance",
        args: [address, env.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS],
      });

      if (allowance < amount) {
        setStatus("Approving ShieldRWAGuard to transfer this token");
        const approveHash = await writeContractAsync({
          address: token,
          abi: erc20Abi,
          functionName: "approve",
          args: [env.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS, amount],
        });
        await publicClient.waitForTransactionReceipt({ hash: approveHash });
      }

      setStatus("Requesting backend attestation");
      const attestResponse = await fetch(`${env.NEXT_PUBLIC_API_BASE_PATH}/attest`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(request),
      });
      const attest = (await attestResponse.json()) as AttestResponse & { error?: string };

      if (!attestResponse.ok || !attest.attestation) {
        throw new Error(attest.error ?? "Backend refused the attestation.");
      }

      setStatus("Waiting for wallet EIP-712 signature");
      const userSig = await signTypedDataAsync({
        account: address,
        domain: {
          name: "ShieldRWAGuard",
          version: "1",
          chainId: chain.id,
          verifyingContract: env.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS,
        },
        types: shieldTransferTypes,
        primaryType: "ShieldTransfer",
        message: {
          token: attest.attestation.token,
          from: address,
          to: attest.attestation.to,
          amount: BigInt(attest.attestation.amount),
          nonce: BigInt(attest.attestation.nonce),
          deadline: BigInt(attest.attestation.deadline),
        },
      });

      setStatus("Sending safeTransfer");
      const txHash = await writeContractAsync({
        address: env.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS,
        abi: shieldRwaGuardAbi,
        functionName: "safeTransfer",
        args: [
          attest.attestation.token as Address,
          address,
          attest.attestation.to,
          BigInt(attest.attestation.amount),
          BigInt(attest.attestation.nonce),
          BigInt(attest.attestation.deadline),
          BigInt(attest.attestation.riskScore),
          userSig,
          attest.attestation.signature,
        ],
      });

      setStatus(`Transaction submitted: ${txHash}`);
      await publicClient.waitForTransactionReceipt({ hash: txHash });
      setStatus(`Transaction confirmed: ${txHash}`);
      onTransaction(txHash);
    } catch (cause) {
      setError(explainContractError(cause));
      setStatus("");
    }
  }

  return (
    <section className="panel">
      <div className="panel-heading">
        <Send size={18} />
        <h2>Execute transaction</h2>
      </div>
      {result?.decision === "WARN" || result?.decision === "REQUIRE_APPROVAL" ? (
        <label className="approval-row">
          <input checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} type="checkbox" />
          <span>Confirm manual review before execution.</span>
        </label>
      ) : null}
      {healthStatus === "loading" ? (
        <div className="notice">
          <ShieldAlert size={16} />
          Checking execution configuration.
        </div>
      ) : null}
      {healthStatus === "error" ? (
        <div className="notice">
          <ShieldAlert size={16} />
          Could not read /api/health. Check the route response before executing on-chain.
        </div>
      ) : null}
      {healthStatus === "ready" && !executionEnabled ? (
        <div className="notice">
          <ShieldAlert size={16} />
          On-chain execution is disabled by env until live token prerequisites are configured.
        </div>
      ) : null}
      {result?.onchainPreview && !result.onchainPreview.canTransfer ? (
        <div className="notice">
          <ShieldAlert size={16} />
          {result.onchainPreview.reason}
        </div>
      ) : null}
      {request && chain && chain.id !== request.chainId ? (
        <div className="notice">
          <ShieldAlert size={16} />
          Switch wallet to chain {request.chainId} before signing typed data.
        </div>
      ) : null}
      <button className="primary-button full" disabled={!canAttempt} onClick={execute} type="button">
        <Send size={16} />
        Execute safeTransfer
      </button>
      {status ? <p className="status-text">{status}</p> : null}
      {error ? <p className="error-text">{error}</p> : null}
    </section>
  );
}
