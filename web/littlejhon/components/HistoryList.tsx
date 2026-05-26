"use client";

import { History } from "lucide-react";
import type { Decision } from "@/lib/types";
import { cn } from "@/components/ui";

export type HistoryItem = {
  simulationId: string;
  decision: Decision;
  riskScore: number;
  scenario: string;
  txHash?: string;
  createdAt: string;
};

export function HistoryList({ items }: { items: HistoryItem[] }) {
  return (
    <section className="panel">
      <div className="panel-heading">
        <History size={18} />
        <h2>History</h2>
      </div>
      <div className="history-list">
        {items.length === 0 ? <p>No simulations yet.</p> : null}
        {items.map((item) => (
          <div className="history-item" key={`${item.simulationId}-${item.createdAt}`}>
            <div>
              <strong>{item.scenario}</strong>
              <span>{item.simulationId}</span>
            </div>
            <span className={cn("decision-chip", item.decision.toLowerCase())}>{item.decision}</span>
            <small>{item.riskScore} risk</small>
          </div>
        ))}
      </div>
    </section>
  );
}
