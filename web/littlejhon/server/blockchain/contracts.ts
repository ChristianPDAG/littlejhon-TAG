import { createPublicClient, http } from "viem";
import type { Address } from "viem";
import { getPublicEnv } from "@/config/env";
import { getDefaultChain } from "@/server/blockchain/chains";

export function getContractAddresses() {
  const env = getPublicEnv();

  return {
    shieldGuard: env.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS,
    complianceRegistry: env.NEXT_PUBLIC_COMPLIANCE_REGISTRY_ADDRESS,
    proofOfReserve: env.NEXT_PUBLIC_PROOF_OF_RESERVE_ADDRESS,
    circuitBreaker: env.NEXT_PUBLIC_CIRCUIT_BREAKER_ADDRESS,
    safetyVault: env.NEXT_PUBLIC_SAFETY_VAULT_ADDRESS,
    governanceTimelock: env.NEXT_PUBLIC_GOVERNANCE_TIMELOCK_ADDRESS,
  } satisfies Record<string, Address>;
}

export function createDefaultPublicClient() {
  const chain = getDefaultChain();
  return createPublicClient({
    chain,
    transport: http(chain.rpcUrls.default.http[0]),
  });
}
