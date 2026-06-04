import type { Address, Hex } from "viem";

export type Decision = "ALLOW" | "WARN" | "REQUIRE_APPROVAL" | "BLOCK";

export type AssetStatus = "official" | "fake" | "restricted" | "suspended" | "unknown";

export type ScenarioId = "safe-transfer" | "unlimited-approval" | "fake-token" | "ineligible-recipient";

export type RiskReason = {
  code: string;
  message: string;
  severity: "info" | "warning" | "critical";
};

export type RiskCheckRequest = {
  chainId: number;
  from: Address;
  to: Address;
  data?: Hex;
  value?: string;
  asset: string;
  token?: Address;
  amount: string;
  context?: {
    action?: "TRANSFER" | "APPROVE" | "TRANSFER_FROM";
    policyId?: string;
    scenarioId?: ScenarioId;
    recipientEligible?: boolean;
    spender?: Address;
  };
};

export type RiskCheckResponse = {
  decision: Decision;
  riskScore: number;
  reasons: RiskReason[];
  humanSummary: string;
  operationHash: Hex;
  policyId: string;
  simulationId: string;
  prerequisites: string[];
  decodedAction: string;
  onchainPreview?: OnchainTransferPreview;
};

export type AttestResponse = RiskCheckResponse & {
  attestation?: {
    token: Address;
    from: Address;
    to: Address;
    amount: string;
    nonce: string;
    deadline: string;
    riskScore: number;
    signer: Address;
    signature: Hex;
  };
};

export type OnchainTransferPreview = {
  checked: boolean;
  executable: boolean;
  canTransfer: boolean;
  reason: string;
  token?: Address;
  transferLimit?: string;
  tokenWhitelisted?: boolean;
  senderVerified?: boolean;
  recipientVerified?: boolean;
  circuitHalted?: boolean;
  reserveBacked?: boolean;
  reserveRatio?: string;
  safetyVaultAllowed?: boolean;
  safetyVaultCap?: string;
  safetyVaultEmergencyDrained?: boolean;
};

export type ContractHealth = {
  codePresent: Record<string, boolean>;
  trustedSignerOnchain: Address | null;
  backendSigner: Address | null;
  signerMatches: boolean;
  maxRiskScoreOnchain: number | null;
  maxRiskScoreEnv: number;
  maxRiskMatches: boolean;
  domainSeparator: Hex | null;
  timelockMinDelay: string | null;
  criticalIssues: string[];
};
