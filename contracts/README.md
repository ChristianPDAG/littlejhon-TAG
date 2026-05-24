# ShieldRWAGuard — Safety Layer for Tokenized RWAs

Solidity 0.8.24 + Foundry contracts that gate every RWA transfer through compliance, reserves,
circuit-breaker, AND an off-chain risk-engine attestation. **Two EIP-712 signatures are required
per transfer**: one from the user, one from a backend "trusted signer" that re-evaluates risk
in real time. The contract enforces an on-chain `maxRiskScore` cap as a defense-in-depth check.

## Architecture (6 contracts)

```
                ┌──────────────────────────────────────────┐
                │           ShieldRWAGuard                 │
                │  (orchestrator + double EIP-712 gate)    │
                └──┬──────────┬──────────┬─────────┬───────┘
                   │          │          │         │
        ┌──────────▼──┐ ┌─────▼──────┐ ┌─▼──────────────┐ ┌────────────┐
        │ Compliance  │ │ ProofOf    │ │ Circuit        │ │ Safety     │
        │ Registry    │ │ Reserve    │ │ Breaker        │ │ Vault      │
        │ (ERC-3643)  │ │ (Chainlink)│ │ (price halts)  │ │ (custody)  │
        └─────────────┘ └────────────┘ └────────────────┘ └────────────┘

                ┌──────────────────────────────────────────┐
                │         GovernanceTimelock               │
                │   (1-day delay for admin actions)        │
                └──────────────────────────────────────────┘
```

See [`deployments/robinhood-testnet.md`](deployments/robinhood-testnet.md) for the live testnet addresses.

## Repo layout

```
contracts/
├── src/
│   ├── ShieldRWAGuard.sol          ← entrypoint: safeTransfer(...)
│   ├── core/                       ← Compliance, PoR, Breaker, Vault, Timelock
│   ├── interfaces/                 ← I*.sol + AggregatorV3Interface
│   ├── libraries/SafetyChecks.sol  ← EIP-712 helpers + reusable validations
│   └── mocks/                      ← MockERC20, MockOracle (test only)
├── script/Deploy.s.sol             ← forge script for full deployment
├── test/
│   ├── unit/                       ← per-contract unit tests
│   ├── integration/FullFlow.t.sol  ← end-to-end transfer scenarios
│   ├── fuzz/                       ← property-based tests (256 runs each)
│   └── invariant/                  ← SafetyVault accounting invariants
└── deployments/                    ← per-network deployment records
```

## Local development

`lib/` is **NOT committed**. After cloning, install dependencies:

```bash
cd contracts
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts --no-commit
forge build
forge test
```

113 tests must pass. Includes 12 fuzz tests (256 runs each) and 3 invariants
(~128k randomized calls per run).

## Deploying

1. `cp .env.example .env`
2. Fill `PRIVATE_KEY` (with `0x` prefix), `TRUSTED_SIGNER`, optional `MAX_RISK_SCORE`
3. Dry-run: `forge script script/Deploy.s.sol --rpc-url $RH_RPC_URL`
4. Broadcast: `forge script script/Deploy.s.sol --rpc-url $RH_RPC_URL --broadcast`

---

# Integration guide

This is the part the backend and frontend teams need.

## How a `safeTransfer` happens end-to-end

```
┌───────────┐   ① intent     ┌──────────────────┐
│  Frontend │───────────────▶│  Backend         │
│  (user)   │                │  Risk Engine     │
└─────┬─────┘                └────┬─────────────┘
      │                           │
      │                           │ ② re-evaluate risk
      │                           │    (compliance, oracle health,
      │                           │     jurisdiction, limits, etc.)
      │                           │
      │   ③ {attestation, sig}    │
      │◀──────────────────────────┘
      │
      │ ④ user signs ShieldTransfer with wallet (EIP-712)
      │
      ▼
┌──────────────────────────────────────────────────┐
│ ShieldRWAGuard.safeTransfer(                     │
│   token, from, to, amount, nonce, deadline,      │
│   riskScore, userSig, attestationSig             │
│ )                                                │
└──────────────────────────────────────────────────┘
        ⑤ verifies BOTH signatures + all on-chain gates
```

**Key invariants the gate enforces (Checks-Effects-Interactions order):**

1. Token whitelisted, amount > 0, recipient ≠ 0
2. `deadline` not expired
3. `nonce` not previously consumed for `from`
4. `riskScore ≤ 100` AND `riskScore ≤ maxRiskScore`
5. `trustedSigner` configured
6. `userSig` recovers to `from` over `ShieldTransfer` typehash
7. `attestationSig` recovers to `trustedSigner` over `RiskAttestation` typehash
8. `from` and `to` both `isVerified` in `ComplianceRegistry` (jurisdiction-aware)
9. CircuitBreaker not halted for `token`
10. ProofOfReserve verifies the token is fully backed
11. `amount ≤ transferLimit` (if a per-token limit is set)

A single `nonce` is consumed for the whole bundle — the same nonce/deadline appear in BOTH signatures.

## EIP-712 domain (both signatures use this)

```js
const domain = {
  name: 'ShieldRWAGuard',
  version: '1',
  chainId: 46630,                                  // Robinhood Chain testnet
  verifyingContract: '0xB4f9C2151B73eDEa730A72e9642C971d803Fd096',
};
```

(Domain separator verified on-chain: `0x756a4734e6316cae2e6d1d328bef3d37319432dc93341bbfc0813b093f65587a`.)

## Frontend — building the user signature (`userSig`)

```js
import { signTypedData } from 'viem/actions';

const types = {
  ShieldTransfer: [
    { name: 'token',    type: 'address' },
    { name: 'from',     type: 'address' },
    { name: 'to',       type: 'address' },
    { name: 'amount',   type: 'uint256' },
    { name: 'nonce',    type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
};

const message = { token, from, to, amount, nonce, deadline };

const userSig = await walletClient.signTypedData({
  account: from,
  domain,
  types,
  primaryType: 'ShieldTransfer',
  message,
});
```

Then call:

```js
await guard.write.safeTransfer([
  token, from, to, amount, nonce, deadline, riskScore, userSig, attestationSig,
]);
```

`riskScore` and `attestationSig` come from the backend (next section).

## Backend — building the attestation signature (`attestationSig`)

The backend holds the `trustedSigner` private key. For every transfer intent it must:

1. **Re-evaluate risk** by reading `ComplianceRegistry.isVerified`, `ProofOfReserve.verifyReserve`,
   `CircuitBreaker.isHalted`, oracle staleness, jurisdiction rules, transfer limits, velocity, etc.
2. **Pick a `riskScore`** in `[0, maxRiskScore]`. If the request should be blocked, refuse to sign
   (the contract will reject any score > `maxRiskScore`).
3. **Sign the `RiskAttestation` struct** with the SAME `nonce` and `deadline` as the user's
   `ShieldTransfer`. The nonce/deadline pair binds the attestation to the exact transfer the user
   approved — the backend cannot endorse anything the user didn't sign.

```ts
import { privateKeyToAccount } from 'viem/accounts';

const trustedSigner = privateKeyToAccount(process.env.TRUSTED_SIGNER_PK);

const types = {
  RiskAttestation: [
    { name: 'token',     type: 'address' },
    { name: 'from',      type: 'address' },
    { name: 'to',        type: 'address' },
    { name: 'amount',    type: 'uint256' },
    { name: 'nonce',     type: 'uint256' },
    { name: 'deadline',  type: 'uint256' },
    { name: 'riskScore', type: 'uint256' },
  ],
};

const attestationSig = await trustedSigner.signTypedData({
  domain,
  types,
  primaryType: 'RiskAttestation',
  message: { token, from, to, amount, nonce, deadline, riskScore },
});

return { attestationSig, riskScore, nonce, deadline };
```

The backend NEVER calls `safeTransfer` itself — it returns the signature to the frontend, which
sends the on-chain tx (paying gas as the user). Same nonce can only be used once.

## Recommended backend endpoint shape

```
POST /attest
Body: { token, from, to, amount }
Resp: { attestationSig, riskScore, nonce, deadline, expiresAt }
Or:   { approved: false, reason: "..." }    // 4xx if blocked
```

Generate `nonce` server-side (monotonic per `from`) and pick a tight `deadline`
(e.g., `now + 5 min`) so unused attestations expire cleanly.

## Reading on-chain state (useful queries)

```bash
# Address of the off-chain risk engine the contract trusts:
cast call $GUARD "trustedSigner()(address)" --rpc-url $RH_RPC_URL

# Max risk score the contract will accept (0-100):
cast call $GUARD "maxRiskScore()(uint256)" --rpc-url $RH_RPC_URL

# Has a nonce already been used?
cast call $GUARD "usedNonces(address,uint256)(bool)" $USER $NONCE --rpc-url $RH_RPC_URL

# Cheap "would this transfer succeed?" simulation (doesn't verify signatures):
cast call $GUARD "canSafeTransfer(address,address,address,uint256,uint256)(bool,string)" \
    $TOKEN $FROM $TO $AMOUNT $RISK_SCORE --rpc-url $RH_RPC_URL
```

## Custom errors the contract emits (catch & translate in UI)

| Selector | When |
|---|---|
| `TokenNotWhitelisted(address)` | Token not in `ShieldRWAGuard.tokenConfigs` |
| `NonceAlreadyUsed(uint256)` | Replay attempt — get a fresh nonce from backend |
| `InvalidSignature(address,address)` | `userSig` doesn't recover to `from` |
| `InvalidAttestation(address,address)` | `attestationSig` doesn't recover to `trustedSigner` |
| `RiskScoreTooHigh(uint256,uint256)` | Backend signed a score above `maxRiskScore` |
| `RiskScoreOutOfRange(uint256)` | Score > 100 — backend bug |
| `TransferExceedsLimit(uint256,uint256)` | `amount` above per-token cap |
| `IdentityNotVerified(address)` | Sender or recipient failed KYC / jurisdiction check |
| `BreakerIsTriggered(address)` | Circuit breaker halted for this token |

## Security caveats

- **Testnet `trustedSigner` is the deployer**. Rotate via `setTrustedSigner(address)` once the
  backend has its own dedicated wallet. The backend key must NEVER touch a chat with an AI
  assistant, a browser env-inspector, a public repo, etc.
- **The `GovernanceTimelock` is deployed but NOT yet owning the other contracts.** All admin
  ops currently bypass the 1-day delay. For mainnet, run `transferOwnership(timelock)` on each
  contract after configuration is settled.
- **Reentrancy** is blocked at `safeTransfer` and vault `deposit`/`withdraw` via OpenZeppelin's
  `ReentrancyGuard` (uses EIP-1153 transient storage on Solidity 0.8.24).
