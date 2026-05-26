"use client";

import { ShieldCheck } from "lucide-react";
import type { DemoScenario } from "@/lib/demo/scenarios";
import type { ScenarioId } from "@/lib/types";
import { cn } from "@/components/ui";

export function ScenarioSelector({
  scenarios,
  selectedId,
  onSelect,
}: {
  scenarios: DemoScenario[];
  selectedId: ScenarioId;
  onSelect: (scenarioId: ScenarioId) => void;
}) {
  return (
    <section className="panel">
      <div className="panel-heading">
        <ShieldCheck size={18} />
        <h2>Scenario runner</h2>
      </div>
      <div className="scenario-grid">
        {scenarios.map((scenario) => (
          <button
            className={cn("scenario-card", selectedId === scenario.id && "selected")}
            key={scenario.id}
            onClick={() => onSelect(scenario.id)}
            type="button"
          >
            <span>{scenario.title}</span>
            <small>{scenario.description}</small>
            <em>{scenario.amountLabel}</em>
          </button>
        ))}
      </div>
    </section>
  );
}
