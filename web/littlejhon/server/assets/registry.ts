import type { Address } from "viem";
import { getPublicEnv, getServerEnv } from "@/config/env";
import type { AssetStatus } from "@/lib/types";
import { getDefaultChain } from "@/server/blockchain/chains";
import { getOnchainTransferPreview } from "@/server/blockchain/onchain";

const FALLBACK_AAPL = "0x1111111111111111111111111111111111111111" as Address;
const FALLBACK_NVDA = "0x2222222222222222222222222222222222222222" as Address;
const FALLBACK_FAKE = "0x3333333333333333333333333333333333333333" as Address;
const RH_E2E_TRWA = "0xc7624150c28bF26cdF920A0715a7c0ba614faE16" as Address;

export type DemoAsset = {
  symbol: string;
  name: string;
  address: Address;
  tokenByChain: Partial<Record<number, Address>>;
  status: AssetStatus;
  decimals: number;
  transferLimit: string;
  issuer: string;
  eligibleRecipients: Address[];
  allowedSpenders: Address[];
  executable: boolean;
  notes: string;
};

export type DemoAssetWithExecution = DemoAsset & {
  executionStatus?: {
    chainId: number;
    token?: Address;
    executable: boolean;
    tokenWhitelisted?: boolean;
    transferLimit?: string;
    circuitHalted?: boolean;
    reserveBacked?: boolean;
    reserveRatio?: string;
    safetyVaultAllowed?: boolean;
    safetyVaultCap?: string;
    safetyVaultEmergencyDrained?: boolean;
    reason: string;
  };
};

export function getDemoAssets(chainId: number = getDefaultChain().id): DemoAsset[] {
  const publicEnv = getPublicEnv();
  const serverEnv = getServerEnv();
  const guard = publicEnv.NEXT_PUBLIC_SHIELD_GUARD_ADDRESS;

  const executableToken = publicEnv.NEXT_PUBLIC_DEMO_TRWA_TOKEN ?? RH_E2E_TRWA;
  const aaplToken = publicEnv.NEXT_PUBLIC_DEMO_AAPL_TOKEN ?? (chainId === 46630 ? executableToken : FALLBACK_AAPL);
  const nvdaToken = publicEnv.NEXT_PUBLIC_DEMO_NVDA_TOKEN ?? FALLBACK_NVDA;
  const fakeToken = publicEnv.NEXT_PUBLIC_DEMO_FAKE_TOKEN ?? FALLBACK_FAKE;

  const assets: DemoAsset[] = [
    {
      symbol: "AAPLx",
      name: "Apple Tokenized Share",
      address: aaplToken,
      tokenByChain: {
        [chainId]: aaplToken,
        46630: executableToken,
      },
      status: "official",
      decimals: 6,
      transferLimit: "100000000",
      issuer: "Tokenized Asset Guard Demo Issuer",
      eligibleRecipients: [
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ],
      allowedSpenders: [guard],
      executable: chainId === 46630,
      notes:
        serverEnv.ASSET_REGISTRY_MODE === "env"
          ? "Official demo asset. Replace with a live whitelisted token through env."
          : "Official demo asset. On Robinhood testnet it maps to the live E2E tRWA token for execution.",
    },
    {
      symbol: "NVDAx",
      name: "Nvidia Tokenized Share",
      address: nvdaToken,
      tokenByChain: {
        [chainId]: nvdaToken,
      },
      status: "restricted",
      decimals: 6,
      transferLimit: "50000000",
      issuer: "Tokenized Asset Guard Demo Issuer",
      eligibleRecipients: ["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
      allowedSpenders: [guard],
      executable: false,
      notes: "Restricted mock asset used to demonstrate recipient eligibility.",
    },
    {
      symbol: "AAPLx-FAKE",
      name: "Spoofed Apple Token",
      address: fakeToken,
      tokenByChain: {
        [chainId]: fakeToken,
      },
      status: "fake",
      decimals: 6,
      transferLimit: "0",
      issuer: "Unknown issuer",
      eligibleRecipients: [],
      allowedSpenders: [],
      executable: false,
      notes: "Known spoofed asset for the fake-token scenario.",
    },
  ];

  return assets;
}

export function findAsset(assetOrAddress: string, chainId: number = getDefaultChain().id) {
  const normalized = assetOrAddress.toLowerCase();
  return getDemoAssets(chainId).find(
    (asset) =>
      asset.symbol.toLowerCase() === normalized ||
      asset.address.toLowerCase() === normalized ||
      Object.values(asset.tokenByChain).some((address) => address?.toLowerCase() === normalized),
  );
}

export function resolveExecutableToken(assetOrAddress: string, chainId: number = getDefaultChain().id): Address | undefined {
  const asset = findAsset(assetOrAddress, chainId);
  if (!asset || !asset.executable) return undefined;
  return asset.tokenByChain[chainId] ?? asset.address;
}

export async function getDemoAssetsWithExecutionStatus(chainId: number = getDefaultChain().id): Promise<DemoAssetWithExecution[]> {
  const assets = getDemoAssets(chainId);
  const probeFrom = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D" as Address;
  const probeTo = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" as Address;

  return Promise.all(
    assets.map(async (asset) => {
      const token = asset.executable ? asset.tokenByChain[chainId] ?? asset.address : undefined;
      const preview = await getOnchainTransferPreview({
        token,
        from: probeFrom,
        to: probeTo,
        amount: BigInt(1),
        riskScore: 12,
      });

      return {
        ...asset,
        executionStatus: {
          chainId,
          token,
          executable: asset.executable && preview.executable,
          tokenWhitelisted: preview.tokenWhitelisted,
          transferLimit: preview.transferLimit,
          circuitHalted: preview.circuitHalted,
          reserveBacked: preview.reserveBacked,
          reserveRatio: preview.reserveRatio,
          safetyVaultAllowed: preview.safetyVaultAllowed,
          safetyVaultCap: preview.safetyVaultCap,
          safetyVaultEmergencyDrained: preview.safetyVaultEmergencyDrained,
          reason: preview.reason,
        },
      };
    }),
  );
}
