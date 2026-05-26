"use client";

import { AlertTriangle, CheckCircle2 } from "lucide-react";
import { useAccount, useSwitchChain } from "wagmi";
import { getPublicEnv } from "@/config/env";
import { getSupportedChains } from "@/server/blockchain/chains";

export function NetworkStatus() {
  const env = getPublicEnv();
  const { chain } = useAccount();
  const { switchChain, isPending } = useSwitchChain();
  const supported = getSupportedChains();
  const isSupported = Boolean(chain && supported.some((item) => item.id === chain.id));

  return (
    <div className="status-row">
      <div className={isSupported ? "status-pill success" : "status-pill warning"}>
        {isSupported ? <CheckCircle2 size={15} /> : <AlertTriangle size={15} />}
        {chain ? chain.name : "Wallet network unknown"}
      </div>
      {!isSupported ? (
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
