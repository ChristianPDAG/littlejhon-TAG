import { describe, expect, it } from "vitest";
import { maxUint256 } from "viem";
import { demoScenarios } from "@/lib/demo/scenarios";
import { evaluateRisk } from "@/server/policies/engine";

const from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D";

describe("policy engine", () => {
  it("allows the safe transfer scenario", () => {
    const request = demoScenarios[0].buildRequest({ chainId: 46630, from });
    const result = evaluateRisk(request);

    expect(result.decision).toBe("ALLOW");
    expect(result.riskScore).toBeLessThanOrEqual(75);
  });

  it("blocks unlimited approvals to unknown spenders", () => {
    const request = demoScenarios[1].buildRequest({ chainId: 46630, from });
    const result = evaluateRisk(request);

    expect(request.amount).toBe(maxUint256.toString());
    expect(result.decision).toBe("BLOCK");
    expect(result.reasons.some((reason) => reason.code === "UNLIMITED_APPROVAL")).toBe(true);
  });

  it("blocks spoofed token assets", () => {
    const request = demoScenarios[2].buildRequest({ chainId: 46630, from });
    const result = evaluateRisk(request);

    expect(result.decision).toBe("BLOCK");
    expect(result.reasons.some((reason) => reason.code === "FAKE_TOKEN")).toBe(true);
  });

  it("requires approval for an ineligible recipient", () => {
    const request = demoScenarios[3].buildRequest({ chainId: 46630, from });
    const result = evaluateRisk(request);

    expect(result.decision).toBe("REQUIRE_APPROVAL");
    expect(result.reasons.some((reason) => reason.code === "RECIPIENT_NOT_ELIGIBLE")).toBe(true);
  });
});
