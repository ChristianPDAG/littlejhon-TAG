"use client";

import { Activity, ExternalLink } from "lucide-react";
import { getPublicEnv } from "@/config/env";
import { shortAddress } from "@/components/ui";

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
};

export function ContractStatus({ health }: { health: Health | null }) {
  const env = getPublicEnv();
  const explorer = health?.chain.explorer ?? env.NEXT_PUBLIC_RH_EXPLORER_URL;
  const contracts = health?.contracts ?? {
    shieldGuard: env.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS,
    complianceRegistry: env.NEXT_PUBLIC_COMPLIANCE_REGISTRY_ADDRESS,
    proofOfReserve: env.NEXT_PUBLIC_PROOF_OF_RESERVE_ADDRESS,
    circuitBreaker: env.NEXT_PUBLIC_CIRCUIT_BREAKER_ADDRESS,
  };

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
        <span>Signer: {shortAddress(health?.signer)}</span>
        <span>Max risk: {health?.maxRiskScore ?? 75}</span>
        <span>{health?.executionEnabled ? "Execution enabled" : "Execution gated by env"}</span>
      </div>
    </section>
  );
}
