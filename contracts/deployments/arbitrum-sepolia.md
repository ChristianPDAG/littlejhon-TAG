# Arbitrum Sepolia — Deployment Record

| Field | Value |
|---|---|
| Network | Arbitrum Sepolia |
| Chain ID | `421614` |
| RPC URL | `https://sepolia-rollup.arbitrum.io/rpc` |
| Explorer | `https://sepolia.arbiscan.io` |
| Bridge from Ethereum Sepolia | `https://bridge.arbitrum.io` |
| Deployer | `0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D` |
| Deploy gas | ~8,378,520 (0.04 gwei → ~0.000125 ETH actual) |

## Deployed contract addresses

> **The addresses below are IDENTICAL to the Robinhood Chain testnet deployment.** The deployer
> wallet had nonce 0 on both chains and ran the same script in the same order, so CREATE produced
> the same addresses. One source of truth for both testnets.

| Contract | Address |
|---|---|
| GovernanceTimelock | `0x78cce8C167583bf358B3EA1c9C409e13A7Da691a` |
| ComplianceRegistry | `0x5886F06c5cD7eC7E07396D4787fca22A965032C5` |
| ProofOfReserve     | `0x5eD6fe0C2bF02227153CC5482f7d316475a11625` |
| CircuitBreaker     | `0x8A65a9ae5057eB846ce06c1E890f0aB8ADB05777` |
| SafetyVault        | `0x99D1beDEa8d628b2Bd1Cd136F3348d1d680D6682` |
| **ShieldRWAGuard** | `0xB4f9C2151B73eDEa730A72e9642C971d803Fd096` |

## ShieldRWAGuard configuration

| Field | Value |
|---|---|
| `owner` | `0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D` |
| `trustedSigner` | `0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D` |
| `maxRiskScore` | `75` (out of 100) |
| EIP-712 domain name | `ShieldRWAGuard` |
| EIP-712 domain version | `1` |
| EIP-712 domain separator | `0xc346a58fd15760d85cbcc7f6d1ddb91a65333ef1d28fae5cb0c204cb39fe8e03` |

> ⚠️ **The domain separator is different from Robinhood's** because it embeds `chainId=421614`.
> Backend and frontend MUST set the right `chainId` in the EIP-712 domain or signatures will fail.
> Use `wagmi`/`viem`'s `chainId` field in the domain — it handles this automatically.

## GovernanceTimelock configuration

Same as Robinhood: `minDelay=86400` (1 day), `GRACE_PERIOD=14 days`, `MAX_DELAY=30 days`.

## Post-deploy checklist (same as Robinhood — must be done per chain)

- [ ] Deploy or identify the actual RWA token contracts
- [ ] `ShieldRWAGuard.whitelistToken(token, transferLimit)`
- [ ] `SafetyVault.allowToken(token, depositCap)`
- [ ] `CircuitBreaker.registerToken(token, priceFeed)`
- [ ] `ProofOfReserve.registerFeed(token, feed, maxStaleness)`
- [ ] `ComplianceRegistry.verifyIdentity(user, jurisdiction, expiry)` for test users
- [ ] (Optional) `transferOwnership(timelock)` on the 5 non-timelock contracts
