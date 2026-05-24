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

## Live deployments

Same six addresses on both testnets (deployer wallet had nonce 0 on each chain, deterministic CREATE):

| Contract | Address (identical on Robinhood + Arbitrum) |
|---|---|
| GovernanceTimelock | `0x78cce8C167583bf358B3EA1c9C409e13A7Da691a` |
| ComplianceRegistry | `0x5886F06c5cD7eC7E07396D4787fca22A965032C5` |
| ProofOfReserve     | `0x5eD6fe0C2bF02227153CC5482f7d316475a11625` |
| CircuitBreaker     | `0x8A65a9ae5057eB846ce06c1E890f0aB8ADB05777` |
| SafetyVault        | `0x99D1beDEa8d628b2Bd1Cd136F3348d1d680D6682` |
| **ShieldRWAGuard** | **`0xB4f9C2151B73eDEa730A72e9642C971d803Fd096`** |

EIP-712 `domainSeparator` differs per chain (it embeds `chainId`):

| Chain | Chain ID | `domainSeparator` |
|---|---|---|
| Robinhood Chain Testnet | `46630`  | `0x756a4734e6316cae2e6d1d328bef3d37319432dc93341bbfc0813b093f65587a` |
| Arbitrum Sepolia        | `421614` | `0xc346a58fd15760d85cbcc7f6d1ddb91a65333ef1d28fae5cb0c204cb39fe8e03` |

Per-chain details: [`deployments/robinhood-testnet.md`](deployments/robinhood-testnet.md), [`deployments/arbitrum-sepolia.md`](deployments/arbitrum-sepolia.md).

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
3. Dry-run on the target network:
   - Robinhood: `forge script script/Deploy.s.sol --rpc-url $RH_RPC_URL`
   - Arbitrum Sepolia: `forge script script/Deploy.s.sol --rpc-url $ARB_SEPOLIA_RPC_URL`
4. Broadcast: append `--broadcast` to either command.

> Tip: if the deployer wallet has `nonce=0` on a chain when you deploy, the resulting addresses
> match the existing deployments because `CREATE` is deterministic in (deployer, nonce). That's
> why both testnets currently share the same six addresses.

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
// Same verifyingContract on both testnets; switch chainId based on the user's wallet.
const domain = {
  name: 'ShieldRWAGuard',
  version: '1',
  chainId: walletClient.chain.id,                          // 46630 or 421614
  verifyingContract: '0xB4f9C2151B73eDEa730A72e9642C971d803Fd096',
};
```

Verified on-chain domain separators:
- Robinhood (46630): `0x756a4734e6316cae2e6d1d328bef3d37319432dc93341bbfc0813b093f65587a`
- Arbitrum Sepolia (421614): `0xc346a58fd15760d85cbcc7f6d1ddb91a65333ef1d28fae5cb0c204cb39fe8e03`

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

## Detailed workflow — what each operation actually does

This section walks through every state-changing operation so the backend and frontend teams
understand the full lifecycle, not just `safeTransfer`.

### 1. Admin onboarding a new RWA token (one-time per token)

The owner of each contract must run, in order:

1. **`ComplianceRegistry.verifyIdentity(user, jurisdiction, expiry)`** — for every user who will
   hold or receive this token. `jurisdiction` is an integer code (e.g., `1`=US, `2`=EU/MiCA).
   Users whose jurisdiction later gets blocked via `blockJurisdiction(j)` immediately fail
   `isVerified` checks, so transfers and deposits revert without an explicit revoke.
2. **`ProofOfReserve.registerFeed(token, feed, maxStaleness)`** — `feed` is a Chainlink PoR
   feed reporting the off-chain reserve balance. `maxStaleness` is in seconds (typical: 1 hour).
3. **`CircuitBreaker.registerToken(token, priceFeed)`** — captures the current price as
   `referencePrice`. Auto-trigger uses the global threshold (default `1500` bps = 15%).
4. **`ShieldRWAGuard.whitelistToken(token, transferLimit)`** — `transferLimit` is the max amount
   per single `safeTransfer` (`0` = unlimited).
5. **`SafetyVault.allowToken(token, cap)`** — `cap` is the max total tokens the vault accepts
   in deposits.

Until **all five** are done, `safeTransfer` and `vault.deposit` will revert.

### 2. End-user flow: signing and submitting a transfer

```
┌───────────┐  POST /attest {token, from, to, amount}      ┌──────────────┐
│ Frontend  │ ──────────────────────────────────────────▶ │ Backend       │
│           │                                              │ Risk Engine   │
│           │ ◀────────────────────────────────────────── │               │
└─────┬─────┘  {attestationSig, riskScore, nonce, deadline} └──────────────┘
      │
      │ (1) wallet.signTypedData(ShieldTransfer)
      │     → userSig
      │
      ▼
ShieldRWAGuard.safeTransfer(
  token, from, to, amount, nonce, deadline, riskScore,
  userSig, attestationSig
)
```

On chain, `safeTransfer` runs these checks in order (each as a revert path):

1. Token is whitelisted
2. `amount > 0`, `to != 0x0`
3. `block.timestamp <= deadline`
4. `usedNonces[from][nonce] == false`
5. `riskScore <= 100` AND `riskScore <= maxRiskScore`
6. `trustedSigner != 0x0`
7. `ecrecover(userSig)` over `ShieldTransfer` digest equals `from`
8. `ecrecover(attestationSig)` over `RiskAttestation` digest equals `trustedSigner`
9. `complianceRegistry.isVerified(from) == true`
10. `complianceRegistry.isVerified(to) == true`
11. `circuitBreaker.isHalted(token) == false`
12. `proofOfReserve.verifyReserve(token) == true`
13. `amount <= transferLimit` (if set)

Only then: `usedNonces[from][nonce] = true`, emit `NonceConsumed`, perform `IERC20.transferFrom`,
emit `SafeTransferExecuted`. Single point of replay protection: the nonce.

### 3. End-user flow: vault deposit / withdraw

`SafetyVault` is the optional custody layer for users who want to keep RWAs inside the safety
perimeter (rather than holding them in their own wallet).

**Deposit** (`vault.deposit(token, amount)`):
1. Token is `allowed` and NOT `emergencyDrained`
2. `amount > 0`
3. `complianceRegistry.isVerified(msg.sender)`
4. Circuit breaker not halted
5. `totalDeposited + amount <= cap`
6. Effects: `balances[token][user] += amount`, `totalDeposited += amount`
7. Interaction: `IERC20.transferFrom(user, vault, amount)`

**Withdraw** (`vault.withdraw(token, amount)`):
1. Same allowed/drained/non-zero checks
2. `balances[token][user] >= amount`
3. Compliance still valid
4. Circuit breaker not halted
5. **`proofOfReserve.verifyReserve(token)` must pass** — extra safety vs raw transfer
6. Effects: decrement balances and totalDeposited
7. Interaction: `IERC20.transfer(user, amount)`

### 4. Operator flow: pausing a token via circuit breaker

Two paths to halt a token, both leading to `CircuitBreaker.state == TRIGGERED`:

- **Manual**: `breaker.triggerBreaker(token, "Reason for halt")` — `onlyOwner`.
- **Auto**: any address calls `breaker.autoTriggerIfNeeded(token)`. If the current oracle price
  deviates from the registered `referencePrice` by ≥ `globalThresholdBps` (default 15%), it
  trips. Typically called by a keeper bot before every batch of operations.

While `TRIGGERED`:
- `safeTransfer` reverts for that token
- `vault.deposit` and `vault.withdraw` revert
- `emergencyDrain` becomes available to the owner

To resume operations: `resolveBreaker(token)` (snapshots new reference price) →
`resetBreaker(token)` (back to `ACTIVE`).

### 5. Operator flow: emergency drain (catastrophic recovery)

If something is so broken that funds must be moved to a safe custodian (e.g., a compromised
oracle, a confirmed exploit), the owner calls — while the circuit breaker is `TRIGGERED`:

```solidity
vault.emergencyDrain(token, rescueDestination);
```

This sweeps the **full** `IERC20.balanceOf(vault)` to `rescueDestination` and sets
`emergencyDrained[token] = true`. After this:

- All deposits and withdraws for that token revert permanently
- User `balances` are preserved on-chain as a record of claims to honor off-chain
  (or via a future migration contract)
- The `totalDeposited` mirror is NOT zeroed — it remains as the canonical liability snapshot

This is intentionally one-way and per-token. For accidentally-sent tokens (excess over
`totalDeposited`), use `rescueExcessTokens` instead — it only touches the unallocated balance
and never harms users.

### 6. Operator flow: changing parameters via timelock

Today, the 5 non-timelock contracts are owned directly by the deployer EOA, so admin actions
take effect immediately. Recommended hardening (planned for next week — see Roadmap below):

1. `contract.transferOwnership(timelock)` for each of the 5 contracts.
2. Future admin actions go through:
   ```
   timelock.schedule(target, abi.encodeWithSelector(...), 0)
   //  ... wait at least minDelay (1 day) ...
   timelock.execute(target, abi.encodeWithSelector(...))
   ```
3. `timelock.cancel(target, data)` aborts a pending op (owner of timelock only).
4. Operations that miss their `GRACE_PERIOD` (14 days) expire and must be re-scheduled.

This guarantees nobody — not even a compromised admin EOA — can change `maxRiskScore`,
`trustedSigner`, transfer limits, breaker thresholds, etc. without a 1-day public delay.

---

## Roadmap — next-week milestones

The contracts are deployed and verified, but the system is not yet operational end-to-end.
This is the work to unblock the full-stack engineer:

### Week 1 — Bring the testnets to life (target: 5-day sprint)

| # | Task | Owner | Blocks |
|---|---|---|---|
| 1 | Deploy `MockERC20` test tokens (TSLA-mock, AMZN-mock, USDG-mock) on both testnets | Contracts | Frontend deposit/withdraw UI |
| 2 | Deploy `MockOracle` price feeds + PoR feeds and wire them via `registerToken` / `registerFeed` | Contracts | Circuit breaker + PoR checks in tests |
| 3 | `whitelistToken` + `allowToken` for each mock RWA on both chains | Contracts | Any safeTransfer in UI |
| 4 | Run `verifyIdentity` for the test users the team uses (≥3 wallets per dev role) | Contracts | UI happy path |
| 5 | Backend `/attest` endpoint signing `RiskAttestation` with the trusted signer key | Backend | safeTransfer in UI |
| 6 | Frontend wallet flow: typed-data sign + safeTransfer submit + error mapping | Frontend | First E2E demo |
| 7 | Generate a **separate** wallet for `trustedSigner`; rotate via `setTrustedSigner(newAddr)` | Contracts + Backend | Production-readiness |
| 8 | `transferOwnership(timelock)` for the 5 non-timelock contracts (after config stable) | Contracts | Audit-readiness |

### Week 2 — Hardening (target: pre-audit posture)

- Increase branch coverage in `CircuitBreaker` (currently 11.5%) — add tests for `resolveBreaker`
  while not triggered, `updateReferencePrice` admin path, edge prices.
- Replace public RPC URLs in `.env.example` with documented Alchemy/Infura paths.
- Block-explorer verification (`forge verify-contract`) on both Robinhood Blockscout and Arbiscan
  so backend + frontend can read ABIs and source from the explorer.
- Optional: Sepolia mainnet-fork test that uses real Chainlink price feeds and OZ governance.
- Optional: `Multicall3` deploy at known address on Robinhood if it's not already there
  (Arbitrum Sepolia already has it at `0xcA11bde05977b3631167028862bE2a173976CA11`).

### What the contracts team needs from full-stack to start work

1. **Backend**: a `trustedSigner` private key generated by the backend team itself (not by us,
   not via this chat). Address only — the contracts team needs the address to call
   `setTrustedSigner`.
2. **Frontend**: list of test user wallet addresses + their jurisdiction codes (1=US, 2=EU)
   so we can `verifyIdentity` them in batch.
3. **Both**: which RWA tickers to mock first (suggested: TSLA, AMZN, USDG).

---

## Security caveats

- **Testnet `trustedSigner` is the deployer**. Rotate via `setTrustedSigner(address)` once the
  backend has its own dedicated wallet. The backend key must NEVER touch a chat with an AI
  assistant, a browser env-inspector, a public repo, etc.
- **The `GovernanceTimelock` is deployed but NOT yet owning the other contracts.** All admin
  ops currently bypass the 1-day delay. For mainnet, run `transferOwnership(timelock)` on each
  contract after configuration is settled.
- **Reentrancy** is blocked at `safeTransfer` and vault `deposit`/`withdraw` via OpenZeppelin's
  `ReentrancyGuard` (uses EIP-1153 transient storage on Solidity 0.8.24).
