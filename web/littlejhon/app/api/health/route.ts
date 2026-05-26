import { NextResponse } from "next/server";
import { getPublicEnv, getServerEnv } from "@/config/env";
import { getContractAddresses } from "@/server/blockchain/contracts";
import { getDefaultChain, getSupportedChains } from "@/server/blockchain/chains";
import { getTrustedSignerAddress } from "@/server/attestations/sign";

export async function GET() {
  const publicEnv = getPublicEnv();
  const serverEnv = getServerEnv();
  const chain = getDefaultChain();

  return NextResponse.json({
    ok: true,
    app: "Tokenized Asset Guard",
    chain,
    supportedChains: getSupportedChains().map((supportedChain) => ({
      id: supportedChain.id,
      name: supportedChain.name,
      explorer: supportedChain.blockExplorers?.default.url,
    })),
    contracts: getContractAddresses(),
    signer: getTrustedSignerAddress(),
    executionEnabled: publicEnv.NEXT_PUBLIC_ENABLE_ONCHAIN_EXECUTION && serverEnv.ENABLE_ONCHAIN_EXECUTION,
    attestationTtlSeconds: serverEnv.ATTESTATION_TTL_SECONDS,
    maxRiskScore: serverEnv.MAX_RISK_SCORE,
  });
}
