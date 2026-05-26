import { NextResponse } from "next/server";
import { getDemoAssets } from "@/server/assets/registry";

export async function GET() {
  return NextResponse.json({
    assets: getDemoAssets(),
  });
}
