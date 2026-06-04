import { NextResponse } from "next/server";
import { getDemoAssetsWithExecutionStatus } from "@/server/assets/registry";
import { getDefaultChain } from "@/server/blockchain/chains";

export async function GET() {
  const chain = getDefaultChain();
  return NextResponse.json({
    chain: {
      id: chain.id,
      name: chain.name,
    },
    assets: await getDemoAssetsWithExecutionStatus(chain.id),
  });
}
