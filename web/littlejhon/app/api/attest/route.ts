import { NextResponse } from "next/server";
import type { Address } from "viem";
import type { RiskCheckRequest } from "@/lib/types";
import { audit } from "@/server/audit/log";
import { findAsset } from "@/server/assets/registry";
import { signRiskAttestation } from "@/server/attestations/sign";
import { evaluateRisk, createNonce } from "@/server/policies/engine";
import { attestRequestSchema } from "@/server/policies/schemas";
import { getServerEnv } from "@/config/env";

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  const parsed = attestRequestSchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      {
        error: "Invalid attest payload",
        issues: parsed.error.flatten(),
      },
      { status: 400 },
    );
  }

  const env = getServerEnv();
  const riskRequest = parsed.data as RiskCheckRequest & {
    nonce?: string;
    deadline?: string;
  };
  const result = evaluateRisk(riskRequest);

  if (result.decision === "BLOCK") {
    audit("attest_refused", {
      simulationId: result.simulationId,
      decision: result.decision,
      riskScore: result.riskScore,
    });

    return NextResponse.json(
      {
        ...result,
        error: "Policy refused to sign a blocked operation.",
      },
      { status: 409 },
    );
  }

  const asset = findAsset(riskRequest.token ?? riskRequest.asset);
  const token = riskRequest.token ?? asset?.address;

  if (!token) {
    return NextResponse.json(
      {
        ...result,
        error: "A token address is required for ShieldRWAGuard attestation.",
      },
      { status: 422 },
    );
  }

  const nonce = BigInt(riskRequest.nonce ?? createNonce(riskRequest));
  const deadline = BigInt(
    riskRequest.deadline ?? Math.floor(Date.now() / 1000 + env.ATTESTATION_TTL_SECONDS).toString(),
  );
  const signed = await signRiskAttestation(
    {
      token: token as Address,
      from: riskRequest.from,
      to: riskRequest.to,
      amount: BigInt(riskRequest.amount),
      nonce,
      deadline,
      riskScore: BigInt(result.riskScore),
    },
    riskRequest.chainId,
  );

  audit("attest_signed", {
    simulationId: result.simulationId,
    signer: signed.signer,
    riskScore: result.riskScore,
  });

  return NextResponse.json({
    ...result,
    attestation: {
      token,
      from: riskRequest.from,
      to: riskRequest.to,
      amount: riskRequest.amount,
      nonce: nonce.toString(),
      deadline: deadline.toString(),
      riskScore: result.riskScore,
      signer: signed.signer,
      signature: signed.signature,
    },
  });
}
