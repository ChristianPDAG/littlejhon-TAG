"use client";

import { Activity, ExternalLink } from "lucide-react";
import { getPublicEnv } from "@/config/env";
import { shortAddress } from "@/components/ui";
import type { OnchainTransferPreview } from "@/lib/types";

type Health = {
  ok: boolean;
  signer: string | null;
  executionEnabled: boolean;
  contracts: Record<string, string>;
  chain: {
    id: number;
    name: string;
    explorer?: string;
  };
  maxRiskScore: number;
  contractHealth?: {
    codePresent: Record<string, boolean>;
    trustedSignerOnchain: string | null;
    backendSigner: string | null;
    signerMatches: boolean;
    maxRiskScoreOnchain: number | null;
    maxRiskScoreEnv: number;
    maxRiskMatches: boolean;
    timelockMinDelay: string | null;
    criticalIssues: string[];
  };
};

export function ContractStatus({
  health,
  preview,
}: {
  health: Health | null;
  preview?: OnchainTransferPreview;
}) {
  const env = getPublicEnv();
  const explorer = health?.chain.explorer ?? env.NEXT_PUBLIC_RH_EXPLORER_URL;
  const contracts = health?.contracts ?? {
    shieldGuard: env.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS,
    complianceRegistry: env.NEXT_PUBLIC_COMPLIANCE_REGISTRY_ADDRESS,
    proofOfReserve: env.NEXT_PUBLIC_PROOF_OF_RESERVE_ADDRESS,
    circuitBreaker: env.NEXT_PUBLIC_CIRCUIT_BREAKER_ADDRESS,
    safetyVault: env.NEXT_PUBLIC_SAFETY_VAULT_ADDRESS,
    governanceTimelock: env.NEXT_PUBLIC_GOVERNANCE_TIMELOCK_ADDRESS,
  };
  const contractHealth = health?.contractHealth;

  return (
    <section className="panel">
      <div className="panel-heading">
        <Activity size={18} />
        <h2>Contracts</h2>
      </div>
      <div className="contract-grid">
        {Object.entries(contracts).map(([name, address]) => (
          <a href={`${explorer}/address/${address}`} key={name} rel="noreferrer" target="_blank">
            <span>{name}</span>
            <strong>{shortAddress(address)}</strong>
            <ExternalLink size={14} />
          </a>
        ))}
      </div>
      <div className="meta-row">
        <span>Backend signer: {shortAddress(contractHealth?.backendSigner ?? health?.signer)}</span>
        <span>Trusted signer: {shortAddress(contractHealth?.trustedSignerOnchain)}</span>
        <span>{contractHealth?.signerMatches ? "Signer match" : "Signer mismatch"}</span>
        <span>Max risk: {health?.maxRiskScore ?? 75}</span>
        <span>{contractHealth?.maxRiskMatches ? "Risk cap match" : "Risk cap mismatch"}</span>
        <span>Timelock min: {contractHealth?.timelockMinDelay ?? "unknown"}s</span>
        <span>{health?.executionEnabled ? "Execution enabled" : "Execution gated by env"}</span>
      </div>
      {contractHealth ? (
        <div className="health-grid">
          {Object.entries(contractHealth.codePresent).map(([name, present]) => (
            <span className={present ? "ok" : "bad"} key={name}>
              {name}: {present ? "code" : "missing"}
            </span>
          ))}
        </div>
      ) : null}
      {contractHealth?.criticalIssues.length ? (
        <div className="prerequisites">
          {contractHealth.criticalIssues.map((issue) => (
            <span key={issue}>{issue}</span>
          ))}
        </div>
      ) : null}
      {preview ? (
        <div className="asset-state">
          <strong>Selected asset</strong>
          <span>{preview.canTransfer ? "Executable safeTransfer" : preview.reason}</span>
          <div className="health-grid">
            <span className={preview.tokenWhitelisted ? "ok" : "bad"}>Whitelist: {String(preview.tokenWhitelisted)}</span>
            <span className={preview.senderVerified ? "ok" : "bad"}>Sender KYC: {String(preview.senderVerified)}</span>
            <span className={preview.recipientVerified ? "ok" : "bad"}>Recipient KYC: {String(preview.recipientVerified)}</span>
            <span className={!preview.circuitHalted ? "ok" : "bad"}>Breaker halted: {String(preview.circuitHalted)}</span>
            <span className={preview.reserveBacked ? "ok" : "bad"}>PoR backed: {String(preview.reserveBacked)}</span>
            <span className={preview.safetyVaultAllowed ? "ok" : "bad"}>Vault allowed: {String(preview.safetyVaultAllowed)}</span>
          </div>
        </div>
      ) : null}
    </section>
  );
}
