"use client";

import { AlertCircle, CheckCircle2, CircleGauge, Lock } from "lucide-react";
import type { RiskCheckResponse } from "@/lib/types";
import { cn } from "@/components/ui";

const decisionIcon = {
  ALLOW: CheckCircle2,
  WARN: AlertCircle,
  REQUIRE_APPROVAL: CircleGauge,
  BLOCK: Lock,
};

export function RiskPanel({ result }: { result: RiskCheckResponse | null }) {
  if (!result) {
    return (
      <section className="panel quiet">
        <div className="panel-heading">
          <CircleGauge size={18} />
          <h2>Risk result</h2>
        </div>
        <p>Select a scenario and run the risk check.</p>
      </section>
    );
  }

  const Icon = decisionIcon[result.decision];

  return (
    <section className={cn("panel risk-panel", result.decision.toLowerCase())}>
      <div className="risk-header">
        <div>
          <div className="panel-heading">
            <Icon size={18} />
            <h2>{result.decision.replace("_", " ")}</h2>
          </div>
          <p>{result.humanSummary}</p>
        </div>
        <div className="score">
          <span>{result.riskScore}</span>
          <small>risk</small>
        </div>
      </div>
      <div className="reason-list">
        {result.reasons.map((reason) => (
          <div className={cn("reason", reason.severity)} key={`${reason.code}-${reason.message}`}>
            <strong>{reason.code}</strong>
            <span>{reason.message}</span>
          </div>
        ))}
      </div>
      {result.prerequisites.length > 0 ? (
        <div className="prerequisites">
          {result.prerequisites.map((item) => (
            <span key={item}>{item}</span>
          ))}
        </div>
      ) : null}
      {result.onchainPreview ? (
        <div className="onchain-preview">
          <strong>{result.onchainPreview.canTransfer ? "On-chain ready" : "On-chain gated"}</strong>
          <span>{result.onchainPreview.reason}</span>
          {result.onchainPreview.token ? <small>Token {result.onchainPreview.token}</small> : null}
        </div>
      ) : null}
    </section>
  );
}
