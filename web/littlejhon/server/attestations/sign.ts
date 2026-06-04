import { privateKeyToAccount } from "viem/accounts";
import type { Address, Hex } from "viem";
import { getServerEnv } from "@/config/env";
import { riskAttestationTypes } from "@/lib/contracts/abis";
import { getDefaultChain } from "@/server/blockchain/chains";
import { getContractAddresses } from "@/server/blockchain/contracts";

export type RiskAttestationMessage = {
  token: Address;
  from: Address;
  to: Address;
  amount: bigint;
  nonce: bigint;
  deadline: bigint;
  riskScore: bigint;
};

function isPrivateKey(value: string | undefined): value is Hex {
  return Boolean(value && /^0x[a-fA-F0-9]{64}$/.test(value));
}

export function getRiskDomain(chainId?: number) {
  const chain = getDefaultChain();
  const addresses = getContractAddresses();

  return {
    name: "ShieldRWAGuard",
    version: "1",
    chainId: chainId ?? chain.id,
    verifyingContract: addresses.shieldGuard,
  } as const;
}

export function getTrustedSignerAddress(): Address | null {
  const env = getServerEnv();
  if (!isPrivateKey(env.TRUSTED_SIGNER_PRIVATE_KEY)) {
    return null;
  }

  return privateKeyToAccount(env.TRUSTED_SIGNER_PRIVATE_KEY).address;
}

export async function signRiskAttestation(message: RiskAttestationMessage, chainId: number) {
  const env = getServerEnv();
  if (!isPrivateKey(env.TRUSTED_SIGNER_PRIVATE_KEY)) {
    throw new Error("A valid TRUSTED_SIGNER_PRIVATE_KEY is required to sign attestations.");
  }

  const signer = privateKeyToAccount(env.TRUSTED_SIGNER_PRIVATE_KEY);
  const signature = await signer.signTypedData({
    domain: getRiskDomain(chainId),
    types: riskAttestationTypes,
    primaryType: "RiskAttestation",
    message,
  });

  return {
    signer: signer.address,
    signature: signature as Hex,
  };
}
