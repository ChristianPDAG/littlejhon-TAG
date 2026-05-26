import { defineChain } from "viem";
import { arbitrumSepolia } from "viem/chains";
import { getPublicEnv } from "@/config/env";

export function getSupportedChains() {
  const env = getPublicEnv();

  const robinhoodTestnet = defineChain({
    id: 46630,
    name: "Robinhood Chain Testnet",
    nativeCurrency: {
      decimals: 18,
      name: "Ether",
      symbol: "ETH",
    },
    rpcUrls: {
      default: {
        http: [env.NEXT_PUBLIC_RH_RPC_URL],
      },
    },
    blockExplorers: {
      default: {
        name: "Robinhood Explorer",
        url: env.NEXT_PUBLIC_RH_EXPLORER_URL,
      },
    },
    testnet: true,
  });

  const configuredArbitrumSepolia = {
    ...arbitrumSepolia,
    rpcUrls: {
      default: {
        http: [env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC_URL],
      },
    },
    blockExplorers: {
      default: {
        name: "Arbiscan Sepolia",
        url: env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_EXPLORER_URL,
      },
    },
  };

  return [robinhoodTestnet, configuredArbitrumSepolia] as const;
}

export function isSupportedChain(chainId: number) {
  return getSupportedChains().some((chain) => chain.id === chainId);
}

export function getDefaultChain() {
  const env = getPublicEnv();
  return getSupportedChains().find((chain) => chain.id === env.NEXT_PUBLIC_DEFAULT_CHAIN_ID) ?? getSupportedChains()[0];
}
