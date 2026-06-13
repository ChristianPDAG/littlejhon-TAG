import type { Metadata } from "next";
import { GuardDashboard } from "@/components/GuardDashboard";

export const metadata: Metadata = {
  title: "tokenized asset guard — demo",
  description: "Risk-check and attestation console for ShieldRWAGuard.",
};

export default function DemoPage() {
  return (
    <div className="min-h-screen bg-[var(--background)] text-[color:var(--foreground)]">
      <GuardDashboard />
    </div>
  );
}
