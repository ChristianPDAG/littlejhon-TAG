import { NextResponse } from "next/server";
import { getPolicy } from "@/server/policies/policy";

export async function GET(_request: Request, context: { params: Promise<{ policyId: string }> }) {
  const { policyId } = await context.params;
  const activePolicy = getPolicy(policyId);

  if (!activePolicy) {
    return NextResponse.json({ error: "Policy not found" }, { status: 404 });
  }

  return NextResponse.json({ policy: activePolicy });
}
