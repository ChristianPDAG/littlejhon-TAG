#!/usr/bin/env bash
# Verify the six ShieldRWAGuard contracts on a target chain explorer.
#
# Usage:
#   bash verify-all.sh robinhood_testnet
#   bash verify-all.sh arbitrum_sepolia
#
# Pre-requisites:
#   - `forge` (Foundry) installed
#   - Repo built: `forge build`
#   - `.env` contains either BLOCKSCOUT_API_KEY (any string works for Blockscout)
#     or ARBISCAN_API_KEY (real key from https://arbiscan.io/myapikey)
#   - foundry.toml has matching entry in [etherscan]

set -euo pipefail

# ─── Args ────────────────────────────────────────────────────────────
CHAIN="${1:-}"
if [ -z "$CHAIN" ]; then
  echo "Usage: bash verify-all.sh <robinhood_testnet|arbitrum_sepolia>"
  exit 1
fi

# ─── Source .env ─────────────────────────────────────────────────────
if [ -f .env ]; then
  set -a; source .env; set +a
fi

case "$CHAIN" in
  robinhood_testnet)
    CHAIN_ID=46630
    VERIFIER=blockscout
    VERIFIER_URL="https://explorer.testnet.chain.robinhood.com/api/"
    EXPLORER="https://explorer.testnet.chain.robinhood.com"
    # Blockscout typically accepts any string as API key
    API_KEY="${BLOCKSCOUT_API_KEY:-anything}"
    ;;
  arbitrum_sepolia)
    CHAIN_ID=421614
    VERIFIER=etherscan
    # Etherscan migrated to a unified V2 API in 2024; the old arbiscan.io endpoint
    # returns HTML instead of JSON. Foundry 1.7.1 doesn't auto-append the required
    # `chainid` query parameter for V2, so we embed it in the URL.
    VERIFIER_URL="https://api.etherscan.io/v2/api?chainid=421614"
    EXPLORER="https://sepolia.arbiscan.io"
    if [ -z "${ARBISCAN_API_KEY:-}" ]; then
      echo "ERROR: ARBISCAN_API_KEY is empty in .env"
      echo "Get a free key at https://arbiscan.io/myapikey"
      exit 1
    fi
    API_KEY="$ARBISCAN_API_KEY"
    ;;
  *)
    echo "Unknown chain '$CHAIN'. Use robinhood_testnet or arbitrum_sepolia."
    exit 1
    ;;
esac

# ─── Deployer + reused addresses ─────────────────────────────────────
DEPLOYER=0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D
TRUSTED=0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D
COMP=0x5886F06c5cD7eC7E07396D4787fca22A965032C5
POR=0x5eD6fe0C2bF02227153CC5482f7d316475a11625
BREAKER=0x8A65a9ae5057eB846ce06c1E890f0aB8ADB05777
VAULT=0x99D1beDEa8d628b2Bd1Cd136F3348d1d680D6682
GUARD=0xB4f9C2151B73eDEa730A72e9642C971d803Fd096
TIMELOCK=0x78cce8C167583bf358B3EA1c9C409e13A7Da691a

# ─── Constructor args (ABI-encoded) ──────────────────────────────────
ARGS_TIMELOCK=$(cast abi-encode "constructor(address,uint256)" "$DEPLOYER" 86400)
ARGS_COMP=$(cast abi-encode "constructor(address)" "$DEPLOYER")
ARGS_POR=$(cast abi-encode "constructor(address)" "$DEPLOYER")
ARGS_BREAKER=$(cast abi-encode "constructor(address)" "$DEPLOYER")
ARGS_VAULT=$(cast abi-encode "constructor(address,address,address,address)" "$DEPLOYER" "$COMP" "$POR" "$BREAKER")
ARGS_GUARD=$(cast abi-encode "constructor(address,address,address,address,address,uint256)" "$DEPLOYER" "$COMP" "$POR" "$BREAKER" "$TRUSTED" 75)

# ─── Common flags ────────────────────────────────────────────────────
COMMON_FLAGS=(
  --chain "$CHAIN_ID"
  --verifier "$VERIFIER"
  --verifier-url "$VERIFIER_URL"
  --etherscan-api-key "$API_KEY"
  --compiler-version "0.8.24"
  --num-of-optimizations 200
  --via-ir
  --watch
  --skip-is-verified-check
)

verify() {
  local ADDR="$1"
  local FQN="$2"        # e.g. src/core/ComplianceRegistry.sol:ComplianceRegistry
  local CARGS="$3"
  local NAME="${FQN##*:}"

  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "  Verifying $NAME"
  echo "  Address : $ADDR"
  echo "  Explorer: $EXPLORER/address/$ADDR"
  echo "════════════════════════════════════════════════════════"

  forge verify-contract "$ADDR" "$FQN" \
    "${COMMON_FLAGS[@]}" \
    --constructor-args "$CARGS" \
    || echo "  ↳ ($NAME failed — may already be verified or need manual upload)"
}

echo "════════════════════════════════════════════════════════"
echo "Verifying 6 contracts on $CHAIN (chainId $CHAIN_ID)"
echo "Verifier : $VERIFIER ($VERIFIER_URL)"
echo "════════════════════════════════════════════════════════"

verify "$TIMELOCK" "src/core/GovernanceTimelock.sol:GovernanceTimelock" "$ARGS_TIMELOCK"
verify "$COMP"     "src/core/ComplianceRegistry.sol:ComplianceRegistry" "$ARGS_COMP"
verify "$POR"      "src/core/ProofOfReserve.sol:ProofOfReserve"         "$ARGS_POR"
verify "$BREAKER"  "src/core/CircuitBreaker.sol:CircuitBreaker"         "$ARGS_BREAKER"
verify "$VAULT"    "src/core/SafetyVault.sol:SafetyVault"               "$ARGS_VAULT"
verify "$GUARD"    "src/ShieldRWAGuard.sol:ShieldRWAGuard"              "$ARGS_GUARD"

echo ""
echo "════════════════════════════════════════════════════════"
echo "Done. Open each address in the explorer to confirm the source tab is green."
echo "  $EXPLORER/address/$GUARD"
echo "════════════════════════════════════════════════════════"
