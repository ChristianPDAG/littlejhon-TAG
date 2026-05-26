import { NextResponse } from "next/server";
import { getPublicEnv, getServerEnv } from "@/config/env";
import { getContractAddresses } from "@/server/blockchain/contracts";
import { getDefaultChain, getSupportedChains } from "@/server/blockchain/chains";
import { getTrustedSignerAddress } from "@/server/attestations/sign";

export async function GET() {
  const publicEnv = getPublicEnv();
  const serverEnv = getServerEnv();
  const chain = getDefaultChain();
  const executionEnabled = publicEnv.NEXT_PUBLIC_ENABLE_ONCHAIN_EXECUTION && serverEnv.ENABLE_ONCHAIN_EXECUTION;

  return NextResponse.json({
    ok: true,
    app: "Tokenized Asset Guard",
    chain: {
      id: chain.id,
      name: chain.name,
      explorer: chain.blockExplorers?.default.url,
    },
    supportedChains: getSupportedChains().map((supportedChain) => ({
      id: supportedChain.id,
      name: supportedChain.name,
      explorer: supportedChain.blockExplorers?.default.url,
    })),
    contracts: getContractAddresses(),
    signer: getTrustedSignerAddress(),
    executionEnabled,
    executionFlags: {
      publicEnabled: publicEnv.NEXT_PUBLIC_ENABLE_ONCHAIN_EXECUTION,
      serverEnabled: serverEnv.ENABLE_ONCHAIN_EXECUTION,
    },
    attestationTtlSeconds: serverEnv.ATTESTATION_TTL_SECONDS,
    maxRiskScore: serverEnv.MAX_RISK_SCORE,
  });
}
