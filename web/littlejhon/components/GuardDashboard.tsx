"use client";

import { RefreshCw, ScanSearch } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { ContractStatus } from "@/components/ContractStatus";
import { ExecutionPanel } from "@/components/ExecutionPanel";
import { HistoryList, type HistoryItem } from "@/components/HistoryList";
import { NetworkStatus } from "@/components/NetworkStatus";
import { RiskPanel } from "@/components/RiskPanel";
import { ScenarioSelector } from "@/components/ScenarioSelector";
import { WalletConnectButton } from "@/components/WalletConnectButton";
import { getPublicEnv } from "@/config/env";
import { useHydrated } from "@/lib/useHydrated";
import { demoScenarios, resolveScenarioToken } from "@/lib/demo/scenarios";
import type { Address } from "viem";
import type { ContractHealth, RiskCheckRequest, RiskCheckResponse, ScenarioId } from "@/lib/types";

const HISTORY_KEY = "tag-demo-history";

type HealthResponse = {
  ok: boolean;
  signer: string | null;
  executionEnabled: boolean;
  contracts: Record<string, string>;
  chain: {
    id: number;
    name: string;
    explorer?: string;
  };
  maxRiskScore: number;
  contractHealth: ContractHealth;
};

export function GuardDashboard() {
  const env = getPublicEnv();
  const { address, chain } = useAccount();
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [healthStatus, setHealthStatus] = useState<"loading" | "ready" | "error">("loading");
  const [selectedId, setSelectedId] = useState<ScenarioId>("safe-transfer");
  const [result, setResult] = useState<RiskCheckResponse | null>(null);
  const [request, setRequest] = useState<RiskCheckRequest | null>(null);
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [isChecking, setIsChecking] = useState(false);
  const [error, setError] = useState("");
  // Wallet address is only known on the client; gate address-dependent UI until
  // hydrated so the server HTML matches the first client render.
  const isHydrated = useHydrated();
  const selectedScenario = useMemo(
    () => demoScenarios.find((scenario) => scenario.id === selectedId) ?? demoScenarios[0],
    [selectedId],
  );

  useEffect(() => {
    fetch(`${env.NEXT_PUBLIC_API_BASE_PATH}/health`)
      .then(async (response) => {
        if (!response.ok) {
          throw new Error("Health endpoint failed.");
        }
        return (await response.json()) as HealthResponse;
      })
      .then((payload) => {
        setHealth(payload);
        setHealthStatus("ready");
      })
      .catch(() => {
        setHealth(null);
        setHealthStatus("error");
      });
    const stored = window.localStorage.getItem(HISTORY_KEY);
    if (stored) {
      // Avoid hydration mismatches by only syncing localStorage after mount.
      const parsed = JSON.parse(stored) as HistoryItem[];
      setTimeout(() => setHistory(parsed), 0);
    }
  }, [env.NEXT_PUBLIC_API_BASE_PATH]);

  function persistHistory(items: HistoryItem[]) {
    setHistory(items);
    window.localStorage.setItem(HISTORY_KEY, JSON.stringify(items));
  }

  async function runRiskCheck() {
    if (!address) {
      setError("Connect a wallet to build a realistic transfer intent.");
      return;
    }

    setError("");
    setIsChecking(true);

    const nextRequest = selectedScenario.buildRequest({
      chainId: chain?.id ?? env.NEXT_PUBLIC_DEFAULT_CHAIN_ID,
      from: address,
      token: resolveScenarioToken({
        scenarioId: selectedId,
        chainId: chain?.id ?? env.NEXT_PUBLIC_DEFAULT_CHAIN_ID,
        envToken: env.NEXT_PUBLIC_DEMO_TRWA_TOKEN as Address | undefined,
      }),
    });

    try {
      const response = await fetch(`${env.NEXT_PUBLIC_API_BASE_PATH}/risk-check`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(nextRequest),
      });
      const payload = (await response.json()) as RiskCheckResponse & { error?: string };

      if (!response.ok) {
        throw new Error(payload.error ?? "Risk check failed.");
      }

      setRequest(nextRequest);
      setResult(payload);
      persistHistory(
        [
          {
            simulationId: payload.simulationId,
            decision: payload.decision,
            riskScore: payload.riskScore,
            scenario: selectedScenario.title,
            createdAt: new Date().toISOString(),
          },
          ...history,
        ].slice(0, 8),
      );
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Risk check failed.");
    } finally {
      setIsChecking(false);
    }
  }

  function handleTransaction(txHash: string) {
    if (!result) return;
    persistHistory(
      history.map((item) => (item.simulationId === result.simulationId ? { ...item, txHash } : item)),
    );
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Tokenized Asset Guard</p>
          <h1>Shielded RWA transfer console</h1>
        </div>
        <div className="topbar-actions">
          <NetworkStatus />
          <WalletConnectButton />
        </div>
      </header>

      <section className="summary-band">
        <div>
          <strong>API analyzes</strong>
          <span>Deterministic policies classify every intent before signing.</span>
        </div>
        <div>
          <strong>Backend attests</strong>
          <span>RiskAttestation matches the deployed ShieldRWAGuard EIP-712 shape.</span>
        </div>
        <div>
          <strong>Contract enforces</strong>
          <span>safeTransfer verifies user signature, backend signature, compliance, PoR and breakers.</span>
        </div>
      </section>

      <div className="workspace-grid">
        <div className="main-column">
          <ScenarioSelector scenarios={demoScenarios} selectedId={selectedId} onSelect={setSelectedId} />
          <section className="panel action-panel">
            <div>
              <div className="panel-heading">
                <ScanSearch size={18} />
                <h2>Selected operation</h2>
              </div>
              <p>
                {selectedScenario.title}: {selectedScenario.description}
              </p>
            </div>
            <button className="primary-button" disabled={!isHydrated || isChecking || !address} onClick={runRiskCheck} type="button">
              <RefreshCw size={16} />
              {isChecking ? "Checking" : "Run risk check"}
            </button>
          </section>
          {error ? <p className="error-text">{error}</p> : null}
          <RiskPanel result={result} />
          <ExecutionPanel
            executionEnabled={healthStatus === "ready" ? health?.executionEnabled ?? false : null}
            healthStatus={healthStatus}
            request={request}
            result={result}
            onTransaction={handleTransaction}
          />
        </div>
        <aside className="side-column">
          <ContractStatus health={health} preview={result?.onchainPreview} />
          <HistoryList items={history} />
        </aside>
      </div>
    </main>
  );
}
