import { randomBytes } from "node:crypto";
import type { Address, Hex, PublicClient } from "viem";
import {
  circuitBreakerAbi,
  complianceRegistryAbi,
  governanceTimelockAbi,
  proofOfReserveAbi,
  safetyVaultAbi,
  shieldRwaGuardAbi,
} from "@/lib/contracts/abis";
import type { ContractHealth, OnchainTransferPreview } from "@/lib/types";
import { getServerEnv } from "@/config/env";
import { getTrustedSignerAddress } from "@/server/attestations/sign";
import { createDefaultPublicClient, getContractAddresses } from "@/server/blockchain/contracts";

const CONTRACT_LABELS = {
  shieldGuard: "ShieldRWAGuard",
  complianceRegistry: "ComplianceRegistry",
  proofOfReserve: "ProofOfReserve",
  circuitBreaker: "CircuitBreaker",
  safetyVault: "SafetyVault",
  governanceTimelock: "GovernanceTimelock",
} as const;

async function safeRead<T>(reader: () => Promise<T>): Promise<T | null> {
  try {
    return await reader();
  } catch {
    return null;
  }
}

export async function getContractHealth(client: PublicClient = createDefaultPublicClient()): Promise<ContractHealth> {
  const env = getServerEnv();
  const addresses = getContractAddresses();
  const backendSigner = getTrustedSignerAddress();
  const entries = Object.entries(addresses) as [keyof typeof addresses, Address][];
  const codeResults = await Promise.all(
    entries.map(async ([key, address]) => {
      const code = await safeRead(() => client.getCode({ address }));
      return [key, Boolean(code && code !== "0x")] as const;
    }),
  );
  const codePresent = Object.fromEntries(codeResults) as Record<string, boolean>;
  const trustedSignerOnchain = await safeRead(() =>
    client.readContract({
      address: addresses.shieldGuard,
      abi: shieldRwaGuardAbi,
      functionName: "trustedSigner",
    }),
  );
  const maxRiskScoreOnchain = await safeRead(async () =>
    Number(
      await client.readContract({
        address: addresses.shieldGuard,
        abi: shieldRwaGuardAbi,
        functionName: "maxRiskScore",
      }),
    ),
  );
  const domainSeparator = await safeRead(() =>
    client.readContract({
      address: addresses.shieldGuard,
      abi: shieldRwaGuardAbi,
      functionName: "domainSeparator",
    }),
  );
  const timelockMinDelay = await safeRead(async () =>
    (
      await client.readContract({
        address: addresses.governanceTimelock,
        abi: governanceTimelockAbi,
        functionName: "minDelay",
      })
    ).toString(),
  );

  const signerMatches =
    Boolean(backendSigner && trustedSignerOnchain) &&
    backendSigner!.toLowerCase() === trustedSignerOnchain!.toLowerCase();
  const maxRiskMatches = maxRiskScoreOnchain === env.MAX_RISK_SCORE;
  const criticalIssues: string[] = [];

  for (const [key, present] of Object.entries(codePresent)) {
    if (!present) criticalIssues.push(`${CONTRACT_LABELS[key as keyof typeof CONTRACT_LABELS] ?? key} bytecode missing`);
  }
  if (!backendSigner) criticalIssues.push("Backend trusted signer key is not configured");
  if (!trustedSignerOnchain) criticalIssues.push("Could not read ShieldRWAGuard.trustedSigner");
  if (backendSigner && trustedSignerOnchain && !signerMatches) criticalIssues.push("Backend signer does not match contract trustedSigner");
  if (maxRiskScoreOnchain === null) criticalIssues.push("Could not read ShieldRWAGuard.maxRiskScore");
  if (maxRiskScoreOnchain !== null && !maxRiskMatches) criticalIssues.push("MAX_RISK_SCORE env does not match contract maxRiskScore");

  return {
    codePresent,
    trustedSignerOnchain: trustedSignerOnchain as Address | null,
    backendSigner,
    signerMatches,
    maxRiskScoreOnchain,
    maxRiskScoreEnv: env.MAX_RISK_SCORE,
    maxRiskMatches,
    domainSeparator: domainSeparator as Hex | null,
    timelockMinDelay,
    criticalIssues,
  };
}

export async function getOnchainTransferPreview(input: {
  token?: Address;
  from: Address;
  to: Address;
  amount: bigint;
  riskScore: number;
  client?: PublicClient;
}): Promise<OnchainTransferPreview> {
  if (!input.token) {
    return {
      checked: false,
      executable: false,
      canTransfer: false,
      reason: "No executable token configured for this chain",
    };
  }

  const client = input.client ?? createDefaultPublicClient();
  const addresses = getContractAddresses();
  const token = input.token;
  const [config, senderVerified, recipientVerified, circuitHalted, reserveBacked, reserveRatio, vaultInfo, emergencyDrained] =
    await Promise.all([
      safeRead(() =>
        client.readContract({
          address: addresses.shieldGuard,
          abi: shieldRwaGuardAbi,
          functionName: "tokenConfigs",
          args: [token],
        }),
      ),
      safeRead(() =>
        client.readContract({
          address: addresses.complianceRegistry,
          abi: complianceRegistryAbi,
          functionName: "isVerified",
          args: [input.from],
        }),
      ),
      safeRead(() =>
        client.readContract({
          address: addresses.complianceRegistry,
          abi: complianceRegistryAbi,
          functionName: "isVerified",
          args: [input.to],
        }),
      ),
      safeRead(() =>
        client.readContract({
          address: addresses.circuitBreaker,
          abi: circuitBreakerAbi,
          functionName: "isHalted",
          args: [token],
        }),
      ),
      safeRead(() =>
        client.readContract({
          address: addresses.proofOfReserve,
          abi: proofOfReserveAbi,
          functionName: "verifyReserve",
          args: [token],
        }),
      ),
      safeRead(() =>
        client.readContract({
          address: addresses.proofOfReserve,
          abi: proofOfReserveAbi,
          functionName: "getReserveRatio",
          args: [token],
        }),
      ),
      safeRead(() =>
        client.readContract({
          address: addresses.safetyVault,
          abi: safetyVaultAbi,
          functionName: "tokens",
          args: [token],
        }),
      ),
      safeRead(() =>
        client.readContract({
          address: addresses.safetyVault,
          abi: safetyVaultAbi,
          functionName: "emergencyDrained",
          args: [token],
        }),
      ),
    ]);

  const [tokenWhitelisted, transferLimit] = config ?? [false, BigInt(0)];
  const [canTransfer, reason] =
    (await safeRead(() =>
      client.readContract({
        address: addresses.shieldGuard,
        abi: shieldRwaGuardAbi,
        functionName: "canSafeTransfer",
        args: [token, input.from, input.to, input.amount, BigInt(input.riskScore)],
      }),
    )) ?? [false, "Could not read ShieldRWAGuard.canSafeTransfer"];

  return {
    checked: true,
    executable: true,
    canTransfer,
    reason,
    token,
    transferLimit: transferLimit.toString(),
    tokenWhitelisted,
    senderVerified: senderVerified ?? false,
    recipientVerified: recipientVerified ?? false,
    circuitHalted: circuitHalted ?? true,
    reserveBacked: reserveBacked ?? false,
    reserveRatio: reserveRatio?.toString(),
    safetyVaultAllowed: vaultInfo?.[0] ?? false,
    safetyVaultCap: vaultInfo?.[1]?.toString(),
    safetyVaultEmergencyDrained: emergencyDrained ?? false,
  };
}

export async function createUnusedNonce(from: Address, attempts = 6): Promise<bigint> {
  const client = createDefaultPublicClient();
  const addresses = getContractAddresses();

  for (let index = 0; index < attempts; index += 1) {
    const nonce = BigInt(`0x${randomBytes(16).toString("hex")}`);
    const used = await safeRead(() =>
      client.readContract({
        address: addresses.shieldGuard,
        abi: shieldRwaGuardAbi,
        functionName: "usedNonces",
        args: [from, nonce],
      }),
    );
    if (!used) return nonce;
  }

  throw new Error("Could not generate an unused ShieldRWAGuard nonce.");
}

export async function isNonceUsed(from: Address, nonce: bigint): Promise<boolean> {
  const client = createDefaultPublicClient();
  const addresses = getContractAddresses();
  return Boolean(
    await safeRead(() =>
      client.readContract({
        address: addresses.shieldGuard,
        abi: shieldRwaGuardAbi,
        functionName: "usedNonces",
        args: [from, nonce],
      }),
    ),
  );
}
