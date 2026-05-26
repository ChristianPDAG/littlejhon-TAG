import type { Address } from "viem";
import { getPublicEnv, getServerEnv } from "@/config/env";
import type { AssetStatus } from "@/lib/types";

const FALLBACK_AAPL = "0x1111111111111111111111111111111111111111" as Address;
const FALLBACK_NVDA = "0x2222222222222222222222222222222222222222" as Address;
const FALLBACK_FAKE = "0x3333333333333333333333333333333333333333" as Address;

export type DemoAsset = {
  symbol: string;
  name: string;
  address: Address;
  status: AssetStatus;
  decimals: number;
  transferLimit: string;
  issuer: string;
  eligibleRecipients: Address[];
  allowedSpenders: Address[];
  notes: string;
};

export function getDemoAssets(): DemoAsset[] {
  const publicEnv = getPublicEnv();
  const serverEnv = getServerEnv();
  const guard = publicEnv.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS;

  const aaplToken = publicEnv.NEXT_PUBLIC_DEMO_AAPL_TOKEN ?? FALLBACK_AAPL;
  const nvdaToken = publicEnv.NEXT_PUBLIC_DEMO_NVDA_TOKEN ?? FALLBACK_NVDA;
  const fakeToken = publicEnv.NEXT_PUBLIC_DEMO_FAKE_TOKEN ?? FALLBACK_FAKE;

  const assets: DemoAsset[] = [
    {
      symbol: "AAPLx",
      name: "Apple Tokenized Share",
      address: aaplToken,
      status: "official",
      decimals: 6,
      transferLimit: "100000000",
      issuer: "Tokenized Asset Guard Demo Issuer",
      eligibleRecipients: [
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ],
      allowedSpenders: [guard],
      notes:
        serverEnv.ASSET_REGISTRY_MODE === "env"
          ? "Official demo asset. Replace with a live whitelisted token through env."
          : "Mock official asset for demo scenarios.",
    },
    {
      symbol: "NVDAx",
      name: "Nvidia Tokenized Share",
      address: nvdaToken,
      status: "restricted",
      decimals: 6,
      transferLimit: "50000000",
      issuer: "Tokenized Asset Guard Demo Issuer",
      eligibleRecipients: ["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
      allowedSpenders: [guard],
      notes: "Restricted mock asset used to demonstrate recipient eligibility.",
    },
    {
      symbol: "AAPLx-FAKE",
      name: "Spoofed Apple Token",
      address: fakeToken,
      status: "fake",
      decimals: 6,
      transferLimit: "0",
      issuer: "Unknown issuer",
      eligibleRecipients: [],
      allowedSpenders: [],
      notes: "Known spoofed asset for the fake-token scenario.",
    },
  ];

  return assets;
}

export function findAsset(assetOrAddress: string) {
  const normalized = assetOrAddress.toLowerCase();
  return getDemoAssets().find(
    (asset) => asset.symbol.toLowerCase() === normalized || asset.address.toLowerCase() === normalized,
  );
}
