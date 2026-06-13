# ShieldRWAGuard — Hackathon API Test Guide

A REST-first safety layer for tokenized real-world assets (RWA) on **Robinhood Chain Testnet** (chain `46630`). Every transfer is screened by a deterministic risk policy **before** it is signed, then enforced again on-chain by `ShieldRWAGuard.safeTransfer` (compliance, proof-of-reserve, circuit breaker, dual EIP-712 signatures, replay protection).

This guide gives a Robinhood reviewer a **copy-paste way to verify the product works**: 15 HTTP cases (no wallet needed), plus one fully on-chain executed transfer.

- **5 cases where the sender / operation is INCORRECT** → the system refuses to sign.
- **1 case where it is CORRECT** → the backend attests and the transfer settles on-chain.

---

## How to reproduce in 3 commands

```bash
cd web/littlejhon
pnpm dev                                   # http://localhost:3000  (loads .env.local)
bash hackathon/test-api.sh                 # runs the 15 HTTP cases, prints PASS/FAIL
```

For the real on-chain transfer (signs + relays a `safeTransfer`):

```bash
node --env-file=.env.local hackathon/onchain.mjs prepare   # one-time: arm breaker + refresh PoR feed
node --env-file=.env.local hackathon/onchain.mjs execute   # attest -> sign -> safeTransfer on-chain
```

> The mock Proof-of-Reserve oracle goes stale after 1h (a real Chainlink PoR feed would not). `prepare` refreshes it and resets the circuit breaker that a previous demo left triggered. `status` prints the live on-chain state.

---

## When is a result "correct"? (the mental model)

There are **two independent gates**. A transfer is only executable when **both** are green:

| Gate | Endpoint | What it answers |
|---|---|---|
| **1. Policy decision** | `/api/risk-check` | Is this operation *allowed by policy*? → `ALLOW` / `WARN` / `REQUIRE_APPROVAL` / `BLOCK` |
| **2. On-chain readiness** | `onchainPreview` inside the same response, and `/api/attest` | Will the *contract* accept it? (token whitelisted, **sender & recipient KYC-verified**, reserve backed, breaker not halted, amount ≤ limit) |

So a "correct sender" means: policy returns `ALLOW` **and** `onchainPreview.canTransfer === true`. The backend only releases an EIP-712 attestation (`/api/attest` → `200`) when both hold. Anything else is "incorrect" and is refused **before** any value moves.

---

## The 6 headline cases (5 incorrect + 1 correct)

| # | Scenario | Why it's (in)correct | `/risk-check` | `/attest` |
|---|---|---|---|---|
| ✅ **C** | **Safe transfer** — official AAPLx, KYC sender → KYC recipient | Policy `ALLOW` + on-chain `canTransfer:true` | `ALLOW` (riskScore **12**) | **200 + signature** → executes |
| ❌ 1 | **Sender not KYC-verified** | Contract requires `ComplianceRegistry.isVerified(from)` | `ALLOW`, but `canTransfer:false` → `Sender not verified` | **409** `Sender not verified` |
| ❌ 2 | **Fake / spoofed token** | Asset flagged `fake` in registry | `BLOCK` (riskScore **96**) | **409** refuses to sign |
| ❌ 3 | **Unlimited approval to unknown spender** | Drains-the-wallet pattern, spender off allowlist | `BLOCK` (riskScore **94**) | **409** refuses to sign |
| ❌ 4 | **Unknown asset** (not in registry) | Can't be screened → untrusted | `BLOCK` (riskScore **92**) | n/a |
| ❌ 5 | **Ineligible recipient** (restricted NVDAx) | Recipient outside eligibility list | `REQUIRE_APPROVAL` (riskScore **72**) | needs manual confirm |

> "Incorrect sender" shows up in **two** layers: pure policy refusals (fake token, unlimited approval, unknown asset, ineligible recipient → cases 2–5) and the **on-chain compliance refusal** (sender/recipient not KYC-verified → case 1). That layered defense is the core value proposition.

---

## All 15 HTTP cases (verified output)

Base URL: `http://localhost:3000`. Addresses used:
`SENDER`=`0xe05f…cfF7` (Alice, KYC-verified), `SENDER_BAD`=`0x0000…DeaDBeef` (never verified), `RECIP_OK`=`0x0376…473c` (Bob, KYC-verified), `tRWA`=`0xc762…faE16`.

### A. Infrastructure / read-only

**01 — Health.** Backend ready, signer matches on-chain `trustedSigner`, execution enabled.
```bash
curl -s http://localhost:3000/api/health
```
→ `200` · `executionEnabled:true` · `signer:0x4e5A…AD6D` · `maxRiskScore:75`. *Criterion: Smart-contract quality (config wired correctly end-to-end).*

**02 — Assets registry.** The three demo assets and their on-chain execution status.
```bash
curl -s http://localhost:3000/api/assets
```
→ `200` · `AAPLx:official, NVDAx:restricted, AAPLx-FAKE:fake`. *Criterion: Product-Market Fit (a curated RWA catalog).*

**03 — Policy document.** The deterministic rule set the engine enforces.
```bash
curl -s http://localhost:3000/api/policies/rwa-retail-v1
```
→ `200` · rules R1–R4 (unlimited approval, spoofed asset, recipient eligibility, unverified destination). *Criterion: Real problem solving (auditable, transparent policy).*

### B. Risk decisions — `POST /api/risk-check`

**04 — ✅ CORRECT safe transfer → `ALLOW`.**
```bash
curl -s -X POST http://localhost:3000/api/risk-check -H "Content-Type: application/json" -d '{
  "chainId":46630,"from":"0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7",
  "to":"0x0376AAc07Ad725E01357B1725B5ceC61aE10473c","asset":"AAPLx",
  "token":"0xc7624150c28bF26cdF920A0715a7c0ba614faE16","amount":"1000000000000000000","value":"0",
  "context":{"action":"TRANSFER","policyId":"rwa-retail-v1","recipientEligible":true}}'
```
→ `200` · `decision:ALLOW` · `riskScore:12` · `onchainPreview.canTransfer:true` (`All checks passed`).

**05 — ❌ Fake token → `BLOCK`.** `asset:"AAPLx-FAKE"`, `token:"0x3333…3333"`.
→ `200` · `decision:BLOCK` · `riskScore:96` · reason `FAKE_TOKEN`.

**06 — ❌ Unlimited approval to unknown spender → `BLOCK`.** `context.action:"APPROVE"`, `amount:<max uint256>`, `spender:"0xdead…beef"`.
→ `200` · `decision:BLOCK` · `riskScore:94`.

**07 — ❌ Unknown asset → `BLOCK`.** `asset:"GOOGLx"` (absent from registry).
→ `200` · `decision:BLOCK` · `riskScore:92`.

**08 — ❌ Unsupported chain → `BLOCK`.** `chainId:1`.
→ `200` · `decision:BLOCK` · `riskScore:95`.

**09 — ❌ Ineligible recipient → `REQUIRE_APPROVAL`.** Restricted `NVDAx` to `0xdddd…dddd`.
→ `200` · `decision:REQUIRE_APPROVAL` · `riskScore:72`.

### C. On-chain gate (sender correctness)

**10 — ❌ Sender NOT KYC-verified.** Same as case 04 but `from:"0x0000…DeaDBeef"`.
→ `200` · `decision:ALLOW` (policy) **but** `onchainPreview.canTransfer:false` · reason **`Sender not verified`**. This is the literal "incorrect sender": policy can't see KYC, the contract can.

**11 — ❌ Malformed sender address → validation error.** `from:"0xnotanaddress"`.
→ `400` (Zod schema rejects it). *Criterion: Smart-contract quality (input validation at the boundary).*

### D. Attestation / signing layer — `POST /api/attest`

**12 — ✅ Attest the correct transfer.** Same body as case 04.
→ `200` · `attestation.signer:0x4e5A…AD6D` · 65-byte EIP-712 `signature`. This signature is what the contract verifies as `attestationSig`.

**13 — ❌ Attest refuses a BLOCK** (fake token, body of case 05).
→ `409` · `error:"Policy refused to sign a blocked operation."` · no signature.

**14 — ❌ Attest refuses an unverified sender** (body of case 10).
→ `409` · `error:"Sender not verified"` (the on-chain gate blocks signing).

**15 — ❌ Attest refuses an approval** (approvals are policy-only; body of case 06).
→ `409` · `error:"Policy refused to sign a blocked operation."`

> Full automated run: `bash hackathon/test-api.sh` → **15 passed, 0 failed**.

---

## The one CORRECT end-to-end execution (on-chain proof)

`hackathon/onchain.mjs execute` performs the real settlement that case 04/12 authorize:

1. `POST /api/attest` → backend returns `decision:ALLOW`, `riskScore:12`, and the trusted-signer EIP-712 signature.
2. The sender (Alice) signs the `ShieldTransfer` typed data with her own key (wallet step).
3. The relayer submits `ShieldRWAGuard.safeTransfer(token, from, to, amount, nonce, deadline, riskScore, userSig, attestationSig)`.

Live result on Robinhood Chain Testnet:

```
decision : ALLOW   riskScore : 12   signer : 0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D
tx hash  : 0x2ba70d4a32dac2c58bb4d12d4300cd1e27fffd9ac0aa6fdc90587245b2c6e2b0   status: success
```

Explorer: `https://explorer.testnet.chain.robinhood.com/tx/0x2ba70d4a32dac2c58bb4d12d4300cd1e27fffd9ac0aa6fdc90587245b2c6e2b0`

The same contract proves the **negative** paths too (replay, risk-too-high, breaker-halted, bad signature) via 113 Foundry tests — see `contracts/` and `E2E-VALIDATION.md`.

---

## Mapping to the judging criteria

| Criterion | Evidence in this suite |
|---|---|
| **Smart-contract quality** | Two independent enforcement layers; `canSafeTransfer` view + `safeTransfer` checks (whitelist, KYC, PoR, breaker, dual EIP-712 sigs, nonce replay). Cases 01, 11, 12, and the on-chain tx. 113 Foundry tests in `contracts/`. |
| **Product-Market Fit** | A drop-in REST API any broker/wallet can call before signing — cases 02–09 show a real RWA catalog and policy decisions without bespoke integration. |
| **Innovation & Creativity** | Risk scoring + a signed off-chain attestation that the contract verifies on-chain (`attestationSig`) — policy and settlement are cryptographically linked (cases 12 + execution). |
| **Real problem solving** | Stops the exact retail-RWA attacks: spoofed tokens (05), wallet-draining approvals (06), non-compliant counterparties (01/10), restricted assets (09). |

---

## Endpoint reference

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/health` | Backend + on-chain readiness, signer, execution flags |
| `GET` | `/api/assets` | Demo RWA registry with per-asset on-chain execution status |
| `GET` | `/api/policies/{policyId}` | The deterministic policy rule set (`rwa-retail-v1`) |
| `POST` | `/api/risk-check` | Screen an intent → decision + risk score + on-chain preview |
| `POST` | `/api/attest` | Sign an `ALLOW` (issues the EIP-712 attestation) or refuse |

**Request shape** (`risk-check` / `attest`):
```jsonc
{
  "chainId": 46630,
  "from": "0x…",            // sender (EVM address)
  "to": "0x…",              // recipient or spender
  "asset": "AAPLx",         // symbol or address in the registry
  "token": "0x…",           // optional explicit ERC-20 to execute against
  "amount": "1000000000000000000",  // string, base units
  "value": "0",
  "context": {
    "action": "TRANSFER",   // TRANSFER | APPROVE | TRANSFER_FROM
    "policyId": "rwa-retail-v1",
    "recipientEligible": true,
    "spender": "0x…"        // for APPROVE
  }
}
```
