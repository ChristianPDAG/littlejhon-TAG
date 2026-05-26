"use client";

import { LogOut, Wallet } from "lucide-react";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { shortAddress } from "@/components/ui";

export function WalletConnectButton() {
  const { address, isConnected } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const connector = connectors[0];

  if (isConnected) {
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
