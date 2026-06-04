import { encodeFunctionData, maxUint256, parseUnits } from "viem";
import type { Address } from "viem";
import { erc20Abi } from "@/lib/contracts/abis";
import type { RiskCheckRequest, ScenarioId } from "@/lib/types";

export type DemoScenario = {
  id: ScenarioId;
  title: string;
  description: string;
  action: "TRANSFER" | "APPROVE";
  asset: string;
  amountLabel: string;
  buildRequest: (input: { chainId: number; from: Address; token?: Address }) => RiskCheckRequest;
};

const ELIGIBLE_RECIPIENT = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" as Address;
const INELIGIBLE_RECIPIENT = "0xdddddddddddddddddddddddddddddddddddddddd" as Address;
const UNKNOWN_SPENDER = "0xdead00000000000000000000000000000000beef" as Address;
const FAKE_TOKEN = "0x3333333333333333333333333333333333333333" as Address;
const RH_E2E_TRWA = "0xc7624150c28bF26cdF920A0715a7c0ba614faE16" as Address;

export function resolveScenarioToken(input: { scenarioId: ScenarioId; chainId: number; envToken?: Address }) {
  if (input.envToken) return input.envToken;
  if (input.scenarioId === "safe-transfer" && input.chainId === 46630) return RH_E2E_TRWA;
  if (input.scenarioId === "fake-token") return FAKE_TOKEN;
  return undefined;
}

export const demoScenarios: DemoScenario[] = [
  {
    id: "safe-transfer",
    title: "Safe transfer",
    description: "Official asset, eligible recipient, supported chain.",
    action: "TRANSFER",
    asset: "AAPLx",
    amountLabel: "25.000000 AAPLx",
    buildRequest: ({ chainId, from, token }) => ({
      chainId,
      from,
      to: ELIGIBLE_RECIPIENT,
      asset: "AAPLx",
      token: token ?? (chainId === 46630 ? RH_E2E_TRWA : undefined),
      amount: parseUnits("25", 6).toString(),
      value: "0",
      context: {
        action: "TRANSFER",
        policyId: "rwa-retail-v1",
        scenarioId: "safe-transfer",
        recipientEligible: true,
      },
    }),
  },
  {
    id: "unlimited-approval",
    title: "Unlimited approval",
    description: "Max approval to a spender outside the allowlist.",
    action: "APPROVE",
    asset: "AAPLx",
    amountLabel: "Unlimited approval",
    buildRequest: ({ chainId, from, token }) => ({
      chainId,
      from,
      to: token ?? UNKNOWN_SPENDER,
      asset: "AAPLx",
      token,
      amount: maxUint256.toString(),
      data: encodeFunctionData({
        abi: erc20Abi,
        functionName: "approve",
        args: [UNKNOWN_SPENDER, maxUint256],
      }),
      value: "0",
      context: {
        action: "APPROVE",
        policyId: "rwa-retail-v1",
        scenarioId: "unlimited-approval",
        spender: UNKNOWN_SPENDER,
      },
    }),
  },
  {
    id: "fake-token",
    title: "Fake token",
    description: "A spoofed asset using familiar RWA branding.",
    action: "TRANSFER",
    asset: "AAPLx-FAKE",
    amountLabel: "10.000000 fake AAPLx",
    buildRequest: ({ chainId, from }) => ({
      chainId,
      from,
      to: ELIGIBLE_RECIPIENT,
      asset: "AAPLx-FAKE",
      token: FAKE_TOKEN,
      amount: parseUnits("10", 6).toString(),
      value: "0",
      context: {
        action: "TRANSFER",
        policyId: "rwa-retail-v1",
        scenarioId: "fake-token",
        recipientEligible: true,
      },
    }),
  },
  {
    id: "ineligible-recipient",
    title: "Ineligible recipient",
    description: "Restricted asset transfer to a recipient outside the eligibility list.",
    action: "TRANSFER",
    asset: "NVDAx",
    amountLabel: "12.000000 NVDAx",
    buildRequest: ({ chainId, from, token }) => ({
      chainId,
      from,
      to: INELIGIBLE_RECIPIENT,
      asset: "NVDAx",
      token,
      amount: parseUnits("12", 6).toString(),
      value: "0",
      context: {
        action: "TRANSFER",
        policyId: "rwa-retail-v1",
        scenarioId: "ineligible-recipient",
        recipientEligible: false,
      },
    }),
  },
];
