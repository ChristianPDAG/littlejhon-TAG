import { NextResponse } from "next/server";
import type { RiskCheckRequest } from "@/lib/types";
import { audit } from "@/server/audit/log";
import { evaluateRisk } from "@/server/policies/engine";
import { riskCheckRequestSchema } from "@/server/policies/schemas";

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  const parsed = riskCheckRequestSchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      {
        error: "Invalid risk-check payload",
        issues: parsed.error.flatten(),
      },
      { status: 400 },
    );
  }

  const result = evaluateRisk(parsed.data as RiskCheckRequest);
  audit("risk_check", {
    simulationId: result.simulationId,
    decision: result.decision,
    riskScore: result.riskScore,
    policyId: result.policyId,
  });

  return NextResponse.json(result);
}
