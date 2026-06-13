"use client";

import { LogOut, Wallet } from "lucide-react";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { shortAddress } from "@/components/ui";
import { useHydrated } from "@/lib/useHydrated";

export function WalletConnectButton() {
  const { address, isConnected } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const connector = connectors[0];

  // Wallet connection state is resolved on the client (wagmi may auto-reconnect).
  // Render the disconnected state until hydrated so SSR HTML matches the first
  // client render and avoids a hydration mismatch.
  const mounted = useHydrated();

  if (mounted && isConnected) {
    return (
      <button className="toolbar-button" onClick={() => disconnect()} type="button">
        <LogOut size={16} />
        {shortAddress(address)}
      </button>
    );
  }

  return (
    <button
      className="primary-button"
      disabled={!connector || isPending}
      onClick={() => connector && connect({ connector })}
      type="button"
    >
      <Wallet size={16} />
      {isPending ? "Connecting" : "Connect wallet"}
    </button>
  );
}
