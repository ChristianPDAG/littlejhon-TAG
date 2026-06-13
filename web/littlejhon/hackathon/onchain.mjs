// On-chain admin + execution helper for the Robinhood testnet demo.
//
// Secrets are loaded from .env.local via Node's --env-file flag — never pass
// the private key on the command line. Run from web/littlejhon:
//
//   node --env-file=.env.local hackathon/onchain.mjs status
//   node --env-file=.env.local hackathon/onchain.mjs reset-breaker
//   node --env-file=.env.local hackathon/onchain.mjs execute
//
// `execute` performs the full "correct sender" path: it asks the local API
// for a backend RiskAttestation, signs the ShieldTransfer with the test
// sender's key, and relays safeTransfer on-chain (deployer pays gas).

import { createPublicClient, createWalletClient, http, defineChain } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const RPC = process.env.NEXT_PUBLIC_RH_RPC_URL ?? "https://rpc.testnet.chain.robinhood.com";
const API = process.env.API_BASE_URL ?? "http://localhost:3000";
const CHAIN_ID = 46630;

const GUARD = "0xB4f9C2151B73eDEa730A72e9642C971d803Fd096";
const COMPLIANCE = "0x5886F06c5cD7eC7E07396D4787fca22A965032C5";
const BREAKER = "0x8A65a9ae5057eB846ce06c1E890f0aB8ADB05777";
const TRWA = "0xc7624150c28bF26cdF920A0715a7c0ba614faE16";
// Mock Proof-of-Reserve oracle deployed during the E2E run. Its data goes stale
// after 1h (registered maxStaleness), so safeTransfer's PoR check needs a fresh
// round. On a live Chainlink PoR feed this refresh is automatic.
const POR_ORACLE = "0x20d770e1e88499e54785B4B9819f3D18add58799";
const RESERVE_ANSWER = 10_000_000n * 10n ** 18n; // 10M reserves >= 10M tRWA supply

// Deterministic Foundry test keys — these are PUBLIC fixtures (same ones used
// in contracts/script/E2EFlow.s.sol), not secrets. Alice is the KYC-verified
// sender funded with tRWA; Bob is the KYC-verified recipient.
const ALICE_PK = "0x" + "A11CE".padStart(64, "0");
const BOB = "0x0376AAc07Ad725E01357B1725B5ceC61aE10473c";
const alice = privateKeyToAccount(ALICE_PK);

const signerPk = process.env.TRUSTED_SIGNER_PRIVATE_KEY;
if (!/^0x[a-fA-F0-9]{64}$/.test(signerPk ?? "")) {
  console.error("TRUSTED_SIGNER_PRIVATE_KEY missing/invalid. Run with: node --env-file=.env.local hackathon/onchain.mjs <cmd>");
  process.exit(1);
}
const relayer = privateKeyToAccount(signerPk); // deployer == trustedSigner on testnet

const chain = defineChain({
  id: CHAIN_ID,
  name: "Robinhood Chain Testnet",
  nativeCurrency: { decimals: 18, name: "Ether", symbol: "ETH" },
  rpcUrls: { default: { http: [RPC] } },
});
const pub = createPublicClient({ chain, transport: http(RPC) });
const wallet = createWalletClient({ account: relayer, chain, transport: http(RPC) });

const breakerAbi = [
  { name: "getState", type: "function", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint8" }] },
  { name: "resolveBreaker", type: "function", stateMutability: "nonpayable", inputs: [{ type: "address" }], outputs: [] },
  { name: "resetBreaker", type: "function", stateMutability: "nonpayable", inputs: [{ type: "address" }], outputs: [] },
];
const complianceAbi = [
  { name: "isVerified", type: "function", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "bool" }] },
];
const guardAbi = [
  {
    name: "canSafeTransfer", type: "function", stateMutability: "view",
    inputs: [{ type: "address" }, { type: "address" }, { type: "address" }, { type: "uint256" }, { type: "uint256" }],
    outputs: [{ type: "bool" }, { type: "string" }],
  },
  {
    name: "tokenConfigs", type: "function", stateMutability: "view",
    inputs: [{ type: "address" }], outputs: [{ type: "bool" }, { type: "uint256" }],
  },
  {
    name: "safeTransfer", type: "function", stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" }, { name: "from", type: "address" }, { name: "to", type: "address" },
      { name: "amount", type: "uint256" }, { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint256" },
      { name: "riskScore", type: "uint256" }, { name: "userSig", type: "bytes" }, { name: "attestationSig", type: "bytes" },
    ],
    outputs: [],
  },
];
const oracleAbi = [
  { name: "setPrice", type: "function", stateMutability: "nonpayable", inputs: [{ type: "int256" }], outputs: [] },
  { name: "latestRoundData", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint80" }, { type: "int256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint80" }] },
];
const shieldTransferTypes = {
  ShieldTransfer: [
    { name: "token", type: "address" }, { name: "from", type: "address" }, { name: "to", type: "address" },
    { name: "amount", type: "uint256" }, { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint256" },
  ],
};

const STATE = ["ACTIVE", "TRIGGERED", "RESOLVED"];

async function status() {
  const [aliceV, bobV, cfg, state, can] = await Promise.all([
    pub.readContract({ address: COMPLIANCE, abi: complianceAbi, functionName: "isVerified", args: [alice.address] }),
    pub.readContract({ address: COMPLIANCE, abi: complianceAbi, functionName: "isVerified", args: [BOB] }),
    pub.readContract({ address: GUARD, abi: guardAbi, functionName: "tokenConfigs", args: [TRWA] }),
    pub.readContract({ address: BREAKER, abi: breakerAbi, functionName: "getState", args: [TRWA] }),
    pub.readContract({ address: GUARD, abi: guardAbi, functionName: "canSafeTransfer", args: [TRWA, alice.address, BOB, 10n ** 18n, 10n] }),
  ]);
  console.log("Sender (Alice)   :", alice.address, "verified:", aliceV);
  console.log("Recipient (Bob)  :", BOB, "verified:", bobV);
  console.log("tRWA whitelisted :", cfg[0], "limit:", cfg[1].toString());
  console.log("Breaker state    :", STATE[Number(state)] ?? state);
  console.log("canSafeTransfer  :", can[0], "-", can[1]);
}

async function resetBreaker() {
  let state = Number(await pub.readContract({ address: BREAKER, abi: breakerAbi, functionName: "getState", args: [TRWA] }));
  console.log("Breaker state before:", STATE[state] ?? state);
  if (state === 1) {
    const h = await wallet.writeContract({ address: BREAKER, abi: breakerAbi, functionName: "resolveBreaker", args: [TRWA] });
    await pub.waitForTransactionReceipt({ hash: h });
    console.log("resolveBreaker tx:", h);
    state = 2;
  }
  if (state === 2) {
    const h = await wallet.writeContract({ address: BREAKER, abi: breakerAbi, functionName: "resetBreaker", args: [TRWA] });
    await pub.waitForTransactionReceipt({ hash: h });
    console.log("resetBreaker tx  :", h);
  }
  const after = Number(await pub.readContract({ address: BREAKER, abi: breakerAbi, functionName: "getState", args: [TRWA] }));
  console.log("Breaker state after :", STATE[after] ?? after);
}

async function refreshReserve() {
  const before = await pub.readContract({ address: POR_ORACLE, abi: oracleAbi, functionName: "latestRoundData" });
  const ageH = Math.round((Math.floor(Date.now() / 1000) - Number(before[3])) / 3600);
  console.log("PoR feed age before:", ageH, "h (maxStaleness 1h)");
  const h = await wallet.writeContract({ address: POR_ORACLE, abi: oracleAbi, functionName: "setPrice", args: [RESERVE_ANSWER] });
  await pub.waitForTransactionReceipt({ hash: h });
  console.log("refresh PoR tx   :", h);
}

async function prepare() {
  await resetBreaker();
  await refreshReserve();
  console.log("--- ready ---");
  await status();
}

async function execute() {
  const amount = process.env.AMOUNT ?? (10n ** 18n).toString(); // default 1 tRWA (18 decimals)
  const body = {
    chainId: CHAIN_ID,
    from: alice.address,
    to: BOB,
    asset: "AAPLx",
    token: TRWA,
    amount,
    value: "0",
    context: { action: "TRANSFER", policyId: "rwa-retail-v1", recipientEligible: true },
  };

  console.log("1) POST /api/attest ...");
  const res = await fetch(`${API}/api/attest`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  if (!res.ok || !json.attestation) {
    console.error("   attest refused:", res.status, json.error ?? json);
    process.exit(1);
  }
  const a = json.attestation;
  console.log("   decision:", json.decision, "riskScore:", a.riskScore, "signer:", a.signer);

  console.log("2) Sender signs ShieldTransfer (EIP-712) ...");
  const userSig = await alice.signTypedData({
    domain: { name: "ShieldRWAGuard", version: "1", chainId: CHAIN_ID, verifyingContract: GUARD },
    types: shieldTransferTypes,
    primaryType: "ShieldTransfer",
    message: {
      token: a.token, from: alice.address, to: a.to,
      amount: BigInt(a.amount), nonce: BigInt(a.nonce), deadline: BigInt(a.deadline),
    },
  });

  console.log("3) Relay safeTransfer on-chain ...");
  const hash = await wallet.writeContract({
    address: GUARD, abi: guardAbi, functionName: "safeTransfer",
    args: [a.token, alice.address, a.to, BigInt(a.amount), BigInt(a.nonce), BigInt(a.deadline), BigInt(a.riskScore), userSig, a.signature],
  });
  const receipt = await pub.waitForTransactionReceipt({ hash });
  console.log("   tx hash :", hash);
  console.log("   status  :", receipt.status);
  console.log("   explorer:", `${process.env.NEXT_PUBLIC_RH_EXPLORER_URL ?? "https://explorer.testnet.chain.robinhood.com"}/tx/${hash}`);
}

const cmd = process.argv[2];
const fns = { status, "reset-breaker": resetBreaker, "refresh-reserve": refreshReserve, prepare, execute };
if (!fns[cmd]) {
  console.error("Usage: node --env-file=.env.local hackathon/onchain.mjs <status|reset-breaker|refresh-reserve|prepare|execute>");
  process.exit(1);
}
fns[cmd]().catch((e) => {
  console.error("ERROR:", e.shortMessage ?? e.message ?? e);
  process.exit(1);
});
