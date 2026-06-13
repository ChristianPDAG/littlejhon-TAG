"use client";

import { AlertTriangle, CheckCircle2 } from "lucide-react";
import { useAccount, useSwitchChain } from "wagmi";
import { getPublicEnv } from "@/config/env";
import { getSupportedChains } from "@/lib/blockchain/chains";
import { useHydrated } from "@/lib/useHydrated";

export function NetworkStatus() {
  const env = getPublicEnv();
  const { chain } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  // Wallet state is only known on the client. Defer wallet-dependent rendering
  // until hydrated so the first client render matches the server HTML and
  // React does not report a hydration mismatch.
  const mounted = useHydrated();

  const supported = getSupportedChains();
  const isSupported = mounted && Boolean(chain && supported.some((item) => item.id === chain.id));
  const networkLabel = mounted && chain ? chain.name : "Wallet network unknown";

  return (
    <div className="status-row">
      <div className={isSupported ? "status-pill success" : "status-pill warning"}>
        {isSupported ? <CheckCircle2 size={15} /> : <AlertTriangle size={15} />}
        {networkLabel}
      </div>
      {mounted && !isSupported ? (
        <button
          className="ghost-button"
          disabled={isPending}
          onClick={() => switchChain({ chainId: env.NEXT_PUBLIC_DEFAULT_CHAIN_ID })}
          type="button"
        >
          Switch to Robinhood testnet
        </button>
      ) : null}
    </div>
  );
}
