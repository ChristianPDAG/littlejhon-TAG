import type { Decision } from "@/lib/types";

export type PolicyRule = {
  id: string;
  decision: Decision;
  title: string;
  description: string;
};

export const DEFAULT_POLICY_ID = "rwa-retail-v1";

export const policy = {
  id: DEFAULT_POLICY_ID,
  name: "RWA Retail Demo Policy",
  maxRiskScore: 75,
  rules: [
    {
      id: "R1",
      decision: "BLOCK",
      title: "Unlimited approval to unknown spender",
      description: "Blocks max uint approvals when the spender is not whitelisted for the asset.",
    },
    {
      id: "R2",
      decision: "BLOCK",
      title: "Unknown or spoofed asset",
      description: "Blocks assets that are not in the official registry or are marked as fake.",
    },
    {
      id: "R3",
      decision: "REQUIRE_APPROVAL",
      title: "Recipient eligibility",
      description: "Requires additional review when the recipient is not eligible for the asset.",
    },
    {
      id: "R4",
      decision: "WARN",
      title: "Unverified destination",
      description: "Warns when the destination is not explicitly recognized by the policy.",
    },
  ] satisfies PolicyRule[],
};

export function getPolicy(policyId = DEFAULT_POLICY_ID) {
  if (policyId !== DEFAULT_POLICY_ID) {
    return null;
  }

  return policy;
}
