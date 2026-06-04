import { decodeFunctionData, encodeAbiParameters, keccak256, maxUint256 } from "viem";
import type { Address, Hex } from "viem";
import { erc20Abi } from "@/lib/contracts/abis";
import type { RiskCheckRequest, RiskCheckResponse, RiskReason } from "@/lib/types";
import { getPublicEnv, getServerEnv } from "@/config/env";
import { findAsset, resolveExecutableToken } from "@/server/assets/registry";
import { isSupportedChain } from "@/server/blockchain/chains";
import { getOnchainTransferPreview } from "@/server/blockchain/onchain";
import { DEFAULT_POLICY_ID } from "@/server/policies/policy";

type DecodedOperation = {
  action: string;
  spender?: Address;
  recipient?: Address;
  amount?: bigint;
};

function decodeOperation(request: RiskCheckRequest): DecodedOperation {
  if (!request.data || request.data === "0x") {
    return {
      action: request.context?.action ?? "TRANSFER",
      spender: request.context?.spender,
      recipient: request.to,
      amount: BigInt(request.amount),
    };
  }

  try {
    const decoded = decodeFunctionData({
      abi: erc20Abi,
      data: request.data,
    });

    if (decoded.functionName === "approve") {
      const [spender, amount] = decoded.args;
      return { action: "APPROVE", spender, amount };
    }

    if (decoded.functionName === "transfer") {
      const [recipient, amount] = decoded.args;
      return { action: "TRANSFER", recipient, amount };
    }

    if (decoded.functionName === "transferFrom") {
      const [, recipient, amount] = decoded.args;
      return { action: "TRANSFER_FROM", recipient, amount };
    }
  } catch {
    return { action: request.context?.action ?? "UNKNOWN", recipient: request.to, amount: BigInt(request.amount) };
  }

  return { action: "UNKNOWN", recipient: request.to, amount: BigInt(request.amount) };
}

function addReason(reasons: RiskReason[], code: string, message: string, severity: RiskReason["severity"]) {
  reasons.push({ code, message, severity });
}

export function buildOperationHash(request: RiskCheckRequest, policyId: string): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { name: "chainId", type: "uint256" },
        { name: "from", type: "address" },
        { name: "to", type: "address" },
        { name: "data", type: "bytes" },
        { name: "value", type: "uint256" },
        { name: "asset", type: "string" },
        { name: "amount", type: "uint256" },
        { name: "policyId", type: "string" },
        { name: "scenarioId", type: "string" },
      ],
      [
        BigInt(request.chainId),
        request.from,
        request.to,
        request.data ?? "0x",
        BigInt(request.value ?? "0"),
        request.asset,
        BigInt(request.amount),
        policyId,
        request.context?.scenarioId ?? "",
      ],
    ),
  );
}

export function createSimulationId(operationHash: Hex): string {
  return `sim_${operationHash.slice(2, 14)}`;
}

export function evaluateRisk(request: RiskCheckRequest): RiskCheckResponse {
  const env = getServerEnv();
  const publicEnv = getPublicEnv();
  const policyId = request.context?.policyId ?? DEFAULT_POLICY_ID;
  const asset = findAsset(request.token ?? request.asset, request.chainId);
  const decoded = decodeOperation(request);
  const reasons: RiskReason[] = [];
  const prerequisites: string[] = [];
  let riskScore = 12;

  if (!isSupportedChain(request.chainId)) {
    addReason(reasons, "UNSUPPORTED_CHAIN", `Chain ${request.chainId} is not configured for this demo.`, "critical");
    riskScore = Math.max(riskScore, 95);
  }

  if (!asset) {
    addReason(reasons, "UNKNOWN_ASSET", "Asset is not present in the official registry.", "critical");
    riskScore = Math.max(riskScore, 92);
  } else if (asset.status === "fake") {
    addReason(reasons, "FAKE_TOKEN", `${asset.symbol} is marked as a spoofed token.`, "critical");
    riskScore = Math.max(riskScore, 96);
  } else if (asset.status === "suspended") {
    addReason(reasons, "ASSET_SUSPENDED", `${asset.symbol} is suspended by policy.`, "critical");
    riskScore = Math.max(riskScore, 90);
  } else if (asset.status === "restricted") {
    addReason(reasons, "RESTRICTED_ASSET", `${asset.symbol} has transfer restrictions.`, "warning");
    riskScore = Math.max(riskScore, 58);
  }

  if (decoded.action === "APPROVE") {
    const spenderAllowed = asset?.allowedSpenders.some(
      (spender) => spender.toLowerCase() === decoded.spender?.toLowerCase(),
    );
    const isUnlimited = decoded.amount === maxUint256;

    if (isUnlimited && !spenderAllowed) {
      addReason(reasons, "UNLIMITED_APPROVAL", "Unlimited approval to a spender outside the allowlist.", "critical");
      riskScore = Math.max(riskScore, 94);
    } else if (!spenderAllowed) {
      addReason(reasons, "UNKNOWN_SPENDER", "Spender is not explicitly allowed for this asset.", "warning");
      riskScore = Math.max(riskScore, 62);
    }
  }

  const recipientEligible =
    request.context?.recipientEligible ??
    Boolean(
      asset?.eligibleRecipients.some((recipient) => recipient.toLowerCase() === request.to.toLowerCase()),
    );

  if (decoded.action !== "APPROVE" && asset && asset.status !== "fake" && !recipientEligible) {
    addReason(reasons, "RECIPIENT_NOT_ELIGIBLE", "Recipient is not eligible for this tokenized asset.", "warning");
    riskScore = Math.max(riskScore, 72);
  }

  const tokenForExecution = request.token ?? resolveExecutableToken(request.asset, request.chainId);
  if (!tokenForExecution) {
    prerequisites.push("Configure a token address before on-chain execution.");
  }

  if (!publicEnv.NEXT_PUBLIC_ENABLE_ONCHAIN_EXECUTION || !env.ENABLE_ONCHAIN_EXECUTION) {
    prerequisites.push("On-chain execution is disabled by env until token whitelist, feeds, and KYC are ready.");
  }

  if (!env.TRUSTED_SIGNER_PRIVATE_KEY) {
    prerequisites.push("Set TRUSTED_SIGNER_PRIVATE_KEY to enable backend attestations.");
  }

  if (!asset || asset.status === "fake" || asset.status === "suspended" || riskScore > env.MAX_RISK_SCORE) {
    const operationHash = buildOperationHash(request, policyId);
    return {
      decision: "BLOCK",
      riskScore,
      reasons,
      humanSummary: "Operation blocked by policy before the wallet signs.",
      operationHash,
      policyId,
      simulationId: createSimulationId(operationHash),
      prerequisites,
      decodedAction: decoded.action,
    };
  }

  if (decoded.action === "APPROVE" && riskScore >= 80) {
    const operationHash = buildOperationHash(request, policyId);
    return {
      decision: "BLOCK",
      riskScore,
      reasons,
      humanSummary: "Approval blocked because it exposes the asset to an untrusted spender.",
      operationHash,
      policyId,
      simulationId: createSimulationId(operationHash),
      prerequisites,
      decodedAction: decoded.action,
    };
  }

  if (!recipientEligible || riskScore >= 70) {
    const operationHash = buildOperationHash(request, policyId);
    return {
      decision: "REQUIRE_APPROVAL",
      riskScore,
      reasons,
      humanSummary: "Operation needs additional approval because the recipient or asset policy is restricted.",
      operationHash,
      policyId,
      simulationId: createSimulationId(operationHash),
      prerequisites,
      decodedAction: decoded.action,
    };
  }

  if (riskScore >= 50) {
    const operationHash = buildOperationHash(request, policyId);
    return {
      decision: "WARN",
      riskScore,
      reasons,
      humanSummary: "Operation can proceed, but the destination is not fully recognized by policy.",
      operationHash,
      policyId,
      simulationId: createSimulationId(operationHash),
      prerequisites,
      decodedAction: decoded.action,
    };
  }

  if (reasons.length === 0) {
    addReason(reasons, "LOW_RISK", "Official asset, eligible recipient, and supported chain.", "info");
  }

  const operationHash = buildOperationHash(request, policyId);
  return {
    decision: "ALLOW",
    riskScore,
    reasons,
    humanSummary: "Operation allowed. The backend can issue a ShieldRWAGuard attestation.",
    operationHash,
    policyId,
    simulationId: createSimulationId(operationHash),
    prerequisites,
    decodedAction: decoded.action,
  };
}

export function createNonce(request: RiskCheckRequest): string {
  const seed = buildOperationHash(request, request.context?.policyId ?? DEFAULT_POLICY_ID);
  return BigInt(`0x${seed.slice(2, 18)}`).toString();
}

export async function evaluateRiskWithOnchain(request: RiskCheckRequest): Promise<RiskCheckResponse> {
  const result = evaluateRisk(request);
  const token = request.token ?? resolveExecutableToken(request.asset, request.chainId);

  if (request.context?.action === "APPROVE" || result.decodedAction === "APPROVE") {
    return {
      ...result,
      onchainPreview: {
        checked: false,
        executable: false,
        canTransfer: false,
        reason: "Approvals are policy-only checks; ShieldRWAGuard executes transfers.",
        token,
      },
    };
  }

  const preview = await getOnchainTransferPreview({
    token,
    from: request.from,
    to: request.to,
    amount: BigInt(request.amount),
    riskScore: result.riskScore,
  });

  return {
    ...result,
    onchainPreview: preview,
    prerequisites:
      preview.canTransfer || result.decision === "BLOCK"
        ? result.prerequisites
        : [...result.prerequisites, `On-chain gate: ${preview.reason}`],
  };
}
