# API Testing — Simulating a real broker integration

This guide shows how a **B2B client (broker, fintech, fund, custodian)** would integrate with the
ShieldRWAGuard API *before* their user signs a transaction. The flow is:

```
Broker's backend       Our API                  ShieldRWAGuard contract
─────────────────      ───────                  ───────────────────────
  user wants                                              │
  to move RWA                                             │
       │                                                  │
       │  POST /api/risk-check        (free, instant)     │
       ├─────────────────────────────►│                   │
       │ ◄─────────────────────────── │ decision: ALLOW   │
       │                                                  │
       │  POST /api/attest                                │
       ├─────────────────────────────►│                   │
       │ ◄─────────────────────────── │ {sig, nonce, ...} │
       │                                                  │
       │ (broker has user sign with their wallet)         │
       │                                                  │
       │  guard.safeTransfer(... userSig, attestationSig) │
       │ ───────────────────────────────────────────────► │
       │                                                  │ ✅
```

The broker pays a subscription fee (or per-call fee) for risk checks + attestations. The contract
will not accept a `safeTransfer` without our attestation signature.

---

## 1. Run the API locally

```powershell
cd web\littlejhon
pnpm install
pnpm dev
# → API live at http://localhost:3000/api
```

Health check (no body):

```powershell
curl http://localhost:3000/api/health
```

---

## 2. The endpoints you'll hit

| Endpoint | Method | Purpose | Auth needed |
|---|---|---|---|
| `/api/health` | GET | Liveness + chain + signer status | No |
| `/api/risk-check` | POST | Evaluate risk WITHOUT signing (read-only) | No (in prod: API key) |
| `/api/attest` | POST | Evaluate + sign a `RiskAttestation` if `ALLOW` | No (in prod: API key) |
| `/api/assets` | GET | List of assets the policy knows about | No |
| `/api/policies/{policyId}` | GET | Describe a policy's rules | No |

For broker simulation: **`/api/risk-check` first**, then **`/api/attest`** if the broker decides
to proceed. The two endpoints accept almost the same body.

---

## 3. Request schema (what the broker MUST send)

```jsonc
{
  "chainId": 46630,                                  // 46630 (Robinhood) or 421614 (Arbitrum Sepolia)
  "from": "0xYourUserWallet...",                     // address signing the tx
  "to": "0xRecipientWallet...",                      // recipient
  "asset": "AAPLx",                                  // ticker as registered in the asset registry
  "token": "0xTokenContract...",                     // OPTIONAL: explicit token address (overrides registry)
  "amount": "25000000",                              // string of base units (e.g. 25 AAPLx with 6 decimals)
  "value": "0",                                      // native value (string) — usually "0"
  "data": "0xa9059cbb000...",                        // OPTIONAL: ABI-encoded calldata for APPROVE/TRANSFER_FROM detection
  "context": {
    "action": "TRANSFER",                            // TRANSFER | APPROVE | TRANSFER_FROM
    "policyId": "rwa-retail-v1",                     // OPTIONAL: which policy ruleset
    "scenarioId": "safe-transfer",                   // OPTIONAL: tag a known scenario
    "recipientEligible": true,                       // OPTIONAL: override eligibility check
    "spender": "0xSpender..."                        // OPTIONAL: required for APPROVE
  }
}
```

`/api/attest` accepts the same body plus optional `nonce` and `deadline` (both as decimal strings).

### Response shape

```jsonc
{
  "decision": "ALLOW",                               // ALLOW | WARN | REQUIRE_APPROVAL | BLOCK
  "riskScore": 12,                                   // 0-100 (lower = safer)
  "reasons": [
    { "code": "LOW_RISK", "message": "Official asset, eligible recipient...", "severity": "info" }
  ],
  "humanSummary": "Operation allowed...",
  "operationHash": "0xab12...",                      // hash of the request — same input = same hash
  "policyId": "rwa-retail-v1",
  "simulationId": "sim_abc123",                      // use this to correlate logs
  "prerequisites": [],                               // things missing for on-chain exec
  "decodedAction": "TRANSFER"
}
```

If you hit `/api/attest` and `decision === "ALLOW"`, you also get:

```jsonc
{
  // ... same fields as above PLUS:
  "attestation": {
    "token": "0x1111...",
    "from": "0xYourUser...",
    "to": "0xRecipient...",
    "amount": "25000000",
    "nonce": "1234567890",
    "deadline": "1735689600",                        // unix seconds
    "riskScore": 12,
    "signer": "0x4e5A...AD6D",                       // who signed (must match trustedSigner on-chain)
    "signature": "0xabcd...1c"                       // pass this as attestationSig to safeTransfer
  }
}
```

---

## 4. Six broker scenarios you can test right now

These use the demo asset addresses baked into the API. Replace `from` with a wallet you control.

### Scenario A — Safe transfer (expect `ALLOW`)

A broker's verified user wants to send 25 AAPLx to an eligible recipient.

**PowerShell:**
```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  asset = "AAPLx"
  amount = "25000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "safe-transfer"
    recipientEligible = $true
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**curl (bash):**
```bash
curl -X POST http://localhost:3000/api/risk-check \
  -H "Content-Type: application/json" \
  -d '{
    "chainId": 46630,
    "from": "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D",
    "to": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "asset": "AAPLx",
    "amount": "25000000",
    "value": "0",
    "context": {
      "action": "TRANSFER",
      "policyId": "rwa-retail-v1",
      "scenarioId": "safe-transfer",
      "recipientEligible": true
    }
  }'
```

**Expected response:** `decision: "ALLOW"`, `riskScore: 12`, reasons include `LOW_RISK`.

---

### Scenario B — Unlimited approval to unknown spender (expect `BLOCK`)

User tries to give unlimited spending power to an address that's NOT in the asset's allowlist.
Classic phishing/drainer pattern.

```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xdead00000000000000000000000000000000beef"
  asset = "AAPLx"
  amount = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
  value = "0"
  context = @{
    action = "APPROVE"
    policyId = "rwa-retail-v1"
    scenarioId = "unlimited-approval"
    spender = "0xdead00000000000000000000000000000000beef"
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**Expected:** `decision: "BLOCK"`, `riskScore: 94`, `reasons[0].code: "UNLIMITED_APPROVAL"`.

The broker should refuse to forward this to the user's wallet.

---

### Scenario C — Spoofed token (expect `BLOCK`)

Same user, same recipient, but the asset is a known fake.

```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  asset = "AAPLx-FAKE"
  amount = "10000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "fake-token"
    recipientEligible = $true
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**Expected:** `decision: "BLOCK"`, `riskScore: 96`, `reasons[0].code: "FAKE_TOKEN"`.

---

### Scenario D — Restricted asset, recipient not in eligibility list (expect `REQUIRE_APPROVAL`)

User wants to send NVDAx to a recipient NOT in NVDAx's eligibility list. Policy escalates instead
of blocking — the broker can ask their compliance officer for manual approval.

```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xdddddddddddddddddddddddddddddddddddddddd"
  asset = "NVDAx"
  amount = "12000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "ineligible-recipient"
    recipientEligible = $false
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**Expected:** `decision: "REQUIRE_APPROVAL"`, `riskScore: 72`, reasons mention restricted asset
and ineligible recipient.

---

### Scenario E — Same operation on Arbitrum Sepolia (expect `ALLOW`)

The API is multi-chain. Change `chainId` from `46630` to `421614` and you target the Arbitrum
deployment instead. Contract address is the same (`0xB4f9C...d096`) but the domain separator
differs.

```powershell
$body = @{
  chainId = 421614
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  asset = "AAPLx"
  amount = "25000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "safe-transfer"
    recipientEligible = $true
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**Expected:** same `ALLOW` shape. If you then call `/api/attest` on Arbitrum, the signature
the API returns binds to the Arbitrum domain separator — the same signature would NOT work on
Robinhood and vice versa.

---

### Scenario F — Get an attestation signature ready to submit on-chain

When the broker has a green-light from `/api/risk-check`, the next call is `/api/attest`. This
returns a backend-signed `RiskAttestation` that the broker (or the user's wallet) passes to
`guard.safeTransfer(...)`.

**Prerequisite:** `TRUSTED_SIGNER_PRIVATE_KEY` must be set in `web/littlejhon/.env`.
Until it is set, this endpoint returns `prerequisites: ["Set TRUSTED_SIGNER_PRIVATE_KEY to enable backend attestations."]`.

```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  asset = "AAPLx"
  amount = "25000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "safe-transfer"
    recipientEligible = $true
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/attest" -Method Post `
  -Body $body -ContentType "application/json"
```

**Expected:** the usual `ALLOW` shape plus an `attestation` object with `nonce`, `deadline`,
`signer`, and `signature`. The broker then asks the user's wallet to sign the matching
`ShieldTransfer` typed data and sends both signatures into `safeTransfer(...)`.

---

## 5. Postman / Insomnia / Bruno

Import this collection (paste as raw):

```json
{
  "info": { "name": "ShieldRWAGuard API", "_postman_id": "shield-rwa-guard" },
  "item": [
    {
      "name": "POST /risk-check — safe transfer",
      "request": {
        "method": "POST",
        "header": [{ "key": "Content-Type", "value": "application/json" }],
        "url": "http://localhost:3000/api/risk-check",
        "body": {
          "mode": "raw",
          "raw": "{\n  \"chainId\": 46630,\n  \"from\": \"0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D\",\n  \"to\": \"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\n  \"asset\": \"AAPLx\",\n  \"amount\": \"25000000\",\n  \"value\": \"0\",\n  \"context\": {\n    \"action\": \"TRANSFER\",\n    \"policyId\": \"rwa-retail-v1\",\n    \"scenarioId\": \"safe-transfer\",\n    \"recipientEligible\": true\n  }\n}"
        }
      }
    },
    {
      "name": "POST /attest — same intent",
      "request": {
        "method": "POST",
        "header": [{ "key": "Content-Type", "value": "application/json" }],
        "url": "http://localhost:3000/api/attest",
        "body": {
          "mode": "raw",
          "raw": "{\n  \"chainId\": 46630,\n  \"from\": \"0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D\",\n  \"to\": \"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\n  \"asset\": \"AAPLx\",\n  \"amount\": \"25000000\",\n  \"value\": \"0\",\n  \"context\": {\n    \"action\": \"TRANSFER\",\n    \"policyId\": \"rwa-retail-v1\",\n    \"scenarioId\": \"safe-transfer\",\n    \"recipientEligible\": true\n  }\n}"
        }
      }
    }
  ]
}
```

---

## 6. What's a "real" broker integration vs the current demo

The current API works against **mock assets** (the registry in [`server/assets/registry.ts`](server/assets/registry.ts)).
A real broker integration adds:

| Today (demo) | Production-ready broker integration |
|---|---|
| Mock addresses `0x1111...`, `0x2222...`, `0x3333...` | Real RWA token contracts whitelisted in `ShieldRWAGuard` |
| `ASSET_REGISTRY_MODE=mock` | `ASSET_REGISTRY_MODE=env` with `NEXT_PUBLIC_DEMO_*_TOKEN` filled |
| `recipientEligible` overridable via body | Eligibility derived from `ComplianceRegistry.isVerified(to)` on-chain |
| No API key | Per-broker API key + rate limit + per-call billing |
| Deployer wallet = trusted signer | Dedicated `trustedSigner` wallet, rotated via `setTrustedSigner` |
| Risk score from in-engine heuristics only | Augmented with external feeds (Chainalysis, TRM, sanctions lists) |
| No replay store | Server-side dedup on `(from, nonce)` to prevent double-attestation |

You can simulate "real" by:

1. Filling `NEXT_PUBLIC_DEMO_AAPL_TOKEN` in `.env` with a real ERC20 you deployed on testnet
2. Setting `ASSET_REGISTRY_MODE=env`
3. Setting `TRUSTED_SIGNER_PRIVATE_KEY` in `.env`
4. Verifying the test wallets via `ComplianceRegistry.verifyIdentity(...)` on-chain
5. Whitelisting that token via `ShieldRWAGuard.whitelistToken(...)`

After that, an `ALLOW` from `/api/attest` will produce a signature that the actual deployed
contract will accept on `safeTransfer(...)`.

---

## 7. Quick sanity table — what every scenario should return

| Scenario body | `decision` | `riskScore` | First reason code |
|---|---|---|---|
| `scenarioId: "safe-transfer"`, AAPLx | `ALLOW` | 12 | `LOW_RISK` |
| `scenarioId: "unlimited-approval"`, max amount | `BLOCK` | 94 | `UNLIMITED_APPROVAL` |
| `scenarioId: "fake-token"`, AAPLx-FAKE | `BLOCK` | 96 | `FAKE_TOKEN` |
| `scenarioId: "ineligible-recipient"`, NVDAx | `REQUIRE_APPROVAL` | 72 | `RESTRICTED_ASSET` |
| Unknown `asset: "DOGEx"` | `BLOCK` | 95 | `UNKNOWN_ASSET` |
| `chainId: 137` (polygon, not configured) | `BLOCK` | 95 | `UNSUPPORTED_CHAIN` |

If any of these comes back different, the policy engine in [`server/policies/engine.ts`](server/policies/engine.ts) has drifted — open it and check.

---

## 8. Monitoring what the API does

The audit log writes to `stdout` (visible in your `pnpm dev` terminal):

```
[audit] risk_check { simulationId: 'sim_ab12cd34ef', decision: 'ALLOW', riskScore: 12, policyId: 'rwa-retail-v1' }
[audit] attest_signed { simulationId: 'sim_ab12cd34ef', signer: '0x4e5A...', riskScore: 12 }
```

In production this would ship to a SIEM / OpenTelemetry. The `simulationId` is your join key
across `/risk-check` → `/attest` → on-chain tx.
