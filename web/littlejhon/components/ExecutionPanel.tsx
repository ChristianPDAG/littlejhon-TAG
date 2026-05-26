"use client";

import { Send, ShieldAlert } from "lucide-react";
import { useMemo, useState } from "react";
import { useAccount, useSignTypedData, useWriteContract } from "wagmi";
import type { Address } from "viem";
import { getPublicEnv } from "@/config/env";
import { shieldRwaGuardAbi, shieldTransferTypes } from "@/lib/contracts/abis";
import type { AttestResponse, RiskCheckRequest, RiskCheckResponse } from "@/lib/types";

export function ExecutionPanel({
  request,
  result,
  onTransaction,
}: {
  request: RiskCheckRequest | null;
  result: RiskCheckResponse | null;
  onTransaction: (txHash: string) => void;
}) {
  const env = getPublicEnv();
  const { address, chain } = useAccount();
  const { signTypedDataAsync } = useSignTypedData();
  const { writeContractAsync } = useWriteContract();
  const [confirmed, setConfirmed] = useState(false);
  const [status, setStatus] = useState<string>("");
  const [error, setError] = useState<string>("");

  const canAttempt = useMemo(() => {
    if (!request || !result || !address || result.decision === "BLOCK") return false;
    if (!env.NEXT_PUBLIC_ENABLE_ONCHAIN_EXECUTION) return false;
    if (result.decision !== "ALLOW" && !confirmed) return false;
    return true;
  }, [address, confirmed, env.NEXT_PUBLIC_ENABLE_ONCHAIN_EXECUTION, request, result]);

  async function execute() {
    if (!request || !result || !address || !chain) return;

    setError("");
    setStatus("Requesting backend attestation");

    try {
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
      onTransaction(txHash);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Execution failed.");
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
      {!env.NEXT_PUBLIC_ENABLE_ONCHAIN_EXECUTION ? (
        <div className="notice">
          <ShieldAlert size={16} />
          On-chain execution is disabled by env until live token prerequisites are configured.
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
