"use client";

import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { getSupportedChains } from "@/lib/blockchain/chains";
import { getPublicEnv } from "@/config/env";

const env = getPublicEnv();
const [robinhoodTestnet, arbitrumSepolia] = getSupportedChains();

export const wagmiConfig = createConfig({
  chains: [robinhoodTestnet, arbitrumSepolia],
  connectors: [injected()],
  transports: {
    [robinhoodTestnet.id]: http(env.NEXT_PUBLIC_RH_RPC_URL),
    [arbitrumSepolia.id]: http(env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC_URL),
  },
});
