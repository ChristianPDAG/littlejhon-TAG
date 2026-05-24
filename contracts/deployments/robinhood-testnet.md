# Robinhood Chain Testnet — Deployment Record

| Field | Value |
|---|---|
| Network | Robinhood Chain Testnet |
| Chain ID | `46630` |
| RPC URL | `https://rpc.testnet.chain.robinhood.com` |
| Explorer | `https://explorer.testnet.chain.robinhood.com` |
| Deployer | `0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D` |
| Deploy gas | ~6,956,881 (0.02 gwei → ~0.000139 ETH) |

## Deployed contract addresses

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
| EIP-712 domain separator | `0x756a4734e6316cae2e6d1d328bef3d37319432dc93341bbfc0813b093f65587a` |

> ⚠️ For testnet only, `trustedSigner` is the same address as the deployer/owner. In a production
> deployment these MUST be separate wallets. Rotate with `setTrustedSigner(address)` once the
> backend risk-engine has its own dedicated signing key.

## GovernanceTimelock configuration

| Field | Value |
|---|---|
| `minDelay` | `86400` (1 day) |
| `GRACE_PERIOD` | `1209600` (14 days, constant) |
| `MAX_DELAY` | `2592000` (30 days, constant) |

## Post-deploy checklist (what still needs to happen)

Before this deployment is functional for end-to-end transfers, the operator must:

- [ ] Deploy or identify the actual RWA token contracts (e.g., TSLA, AMZN tokens)
- [ ] `ShieldRWAGuard.whitelistToken(token, transferLimit)` for each RWA
- [ ] `SafetyVault.allowToken(token, depositCap)` for each RWA
- [ ] Deploy or register the Chainlink price feed for each RWA in `CircuitBreaker.registerToken`
- [ ] Deploy or register the Chainlink Proof-of-Reserve feed in `ProofOfReserve.registerFeed`
- [ ] `ComplianceRegistry.verifyIdentity(user, jurisdiction, expiry)` for each KYC-verified user
- [ ] (Optional, recommended) Transfer ownership of the 5 non-timelock contracts to the
      `GovernanceTimelock` so future admin changes go through the 1-day delay
