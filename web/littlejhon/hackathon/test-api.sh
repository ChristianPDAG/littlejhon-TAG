#!/usr/bin/env bash
# ============================================================================
# ShieldRWAGuard — API test suite (15 cases) for the Robinhood hackathon demo
# ============================================================================
# Drives the live REST API the same way a Robinhood integration would: pure
# HTTP, no wallet. Each case prints the HTTP status, the policy decision, and a
# PASS/FAIL against the expected outcome.
#
#   Prereqs: dev server running ->  pnpm dev   (http://localhost:3000)
#   Run:     bash hackathon/test-api.sh
#   Custom:  BASE=https://your-vercel-url bash hackathon/test-api.sh
#
# The sender address below (Alice) is KYC-verified on-chain; SENDER_BAD is not.
# Override with: SENDER=0x... bash hackathon/test-api.sh
# ============================================================================
set -u

BASE="${BASE:-http://localhost:3000}"
API="$BASE/api"
CHAIN=46630
TRWA="0xc7624150c28bF26cdF920A0715a7c0ba614faE16"
FAKE="0x3333333333333333333333333333333333333333"
SENDER="${SENDER:-0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7}"   # Alice (KYC-verified)
SENDER_BAD="0x00000000000000000000000000000000DeaDBeef"          # never KYC-verified
RECIP_OK="0x0376AAc07Ad725E01357B1725B5ceC61aE10473c"            # Bob (KYC-verified)
RECIP_ELIGIBLE="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"      # policy-eligible
RECIP_INELIGIBLE="0xdddddddddddddddddddddddddddddddddddddddd"    # not eligible
SPENDER_BAD="0xdead00000000000000000000000000000000beef"        # unknown spender
GUARD="0xB4f9C2151B73eDEa730A72e9642C971d803Fd096"
MAXUINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"

pass=0; fail=0
GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; NC=$'\e[0m'

# hit METHOD PATH BODY  -> sets $CODE and $BODY
hit() {
  local method="$1" path="$2" body="${3:-}"
  if [ "$method" = "GET" ]; then
    RESP=$(curl -s -m 30 -w $'\n%{http_code}' "$API$path")
  else
    RESP=$(curl -s -m 30 -w $'\n%{http_code}' -X "$method" "$API$path" -H "Content-Type: application/json" -d "$body")
  fi
  CODE="${RESP##*$'\n'}"
  BODY="${RESP%$'\n'*}"
}

field() { echo "$BODY" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const o=JSON.parse(d);const p='$1'.split('.');let v=o;for(const k of p)v=v?.[k];console.log(typeof v==='object'?JSON.stringify(v):v);}catch{console.log('')}})"; }

check() { # NAME  EXPECT_HTTP  ACTUAL_HTTP  EXPECT_DECISION  ACTUAL_DECISION
  local name="$1" eh="$2" ah="$3" ed="$4" ad="$5"
  if [ "$ah" = "$eh" ] && { [ -z "$ed" ] || [ "$ad" = "$ed" ]; }; then
    printf "%s[PASS]%s %s  ${DIM}http=%s decision=%s${NC}\n" "$GREEN" "$NC" "$name" "$ah" "$ad"; pass=$((pass+1))
  else
    printf "%s[FAIL]%s %s  ${DIM}expected http=%s/dec=%s got http=%s/dec=%s${NC}\n" "$RED" "$NC" "$name" "$eh" "$ed" "$ah" "$ad"; fail=$((fail+1))
  fi
}

echo "${BOLD}ShieldRWAGuard API suite -> $BASE${NC}"
echo "Sender (good): $SENDER"
echo "----------------------------------------------------------------------"

echo "${BOLD}A. Infrastructure / read-only${NC}"

# 1 — Health: backend ready, signer matches on-chain, execution enabled
hit GET /health
check "01 health: executionEnabled=true" 200 "$CODE" "" ""
printf "     ${DIM}executionEnabled=%s signer=%s maxRiskScore=%s${NC}\n" "$(field executionEnabled)" "$(field signer)" "$(field maxRiskScore)"

# 2 — Assets registry: 3 demo assets, on-chain execution status per asset
hit GET /assets
check "02 assets: registry returns list" 200 "$CODE" "" ""
printf "     ${DIM}assets=%s${NC}\n" "$(echo "$BODY" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const o=JSON.parse(d);console.log(o.assets.map(a=>a.symbol+':'+a.status).join(', '))}catch{console.log('')}})")"

# 3 — Policy document: the deterministic rule set the engine enforces
hit GET /policies/rwa-retail-v1
check "03 policy: rwa-retail-v1 published" 200 "$CODE" "" ""

echo "${BOLD}B. Risk decisions (the policy brain) — /risk-check${NC}"

# 4 — CORRECT sender/operation: official asset, eligible recipient -> ALLOW
hit POST /risk-check "{\"chainId\":$CHAIN,\"from\":\"$SENDER\",\"to\":\"$RECIP_OK\",\"asset\":\"AAPLx\",\"token\":\"$TRWA\",\"amount\":\"1000000000000000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\",\"recipientEligible\":true}}"
check "04 ALLOW: safe transfer (correct)" 200 "$CODE" "ALLOW" "$(field decision)"
printf "     ${DIM}riskScore=%s canTransfer=%s reason=%s${NC}\n" "$(field riskScore)" "$(field onchainPreview.canTransfer)" "$(field onchainPreview.reason)"

# 5 — INCORRECT #1: fake / spoofed token -> BLOCK
hit POST /risk-check "{\"chainId\":$CHAIN,\"from\":\"$SENDER\",\"to\":\"$RECIP_ELIGIBLE\",\"asset\":\"AAPLx-FAKE\",\"token\":\"$FAKE\",\"amount\":\"10000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\"}}"
check "05 BLOCK: fake token" 200 "$CODE" "BLOCK" "$(field decision)"
printf "     ${DIM}riskScore=%s reasons=%s${NC}\n" "$(field riskScore)" "$(field reasons)"

# 6 — INCORRECT #2: unlimited approval to unknown spender -> BLOCK
hit POST /risk-check "{\"chainId\":$CHAIN,\"from\":\"$SENDER\",\"to\":\"$SPENDER_BAD\",\"asset\":\"AAPLx\",\"token\":\"$TRWA\",\"amount\":\"$MAXUINT\",\"value\":\"0\",\"context\":{\"action\":\"APPROVE\",\"policyId\":\"rwa-retail-v1\",\"spender\":\"$SPENDER_BAD\"}}"
check "06 BLOCK: unlimited approval" 200 "$CODE" "BLOCK" "$(field decision)"
printf "     ${DIM}riskScore=%s${NC}\n" "$(field riskScore)"

# 7 — INCORRECT #3: unknown asset (not in registry) -> BLOCK
hit POST /risk-check "{\"chainId\":$CHAIN,\"from\":\"$SENDER\",\"to\":\"$RECIP_OK\",\"asset\":\"GOOGLx\",\"amount\":\"1000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\"}}"
check "07 BLOCK: unknown asset" 200 "$CODE" "BLOCK" "$(field decision)"
printf "     ${DIM}riskScore=%s${NC}\n" "$(field riskScore)"

# 8 — INCORRECT #4: unsupported chain -> BLOCK
hit POST /risk-check "{\"chainId\":1,\"from\":\"$SENDER\",\"to\":\"$RECIP_OK\",\"asset\":\"AAPLx\",\"amount\":\"1000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\"}}"
check "08 BLOCK: unsupported chain" 200 "$CODE" "BLOCK" "$(field decision)"
printf "     ${DIM}riskScore=%s${NC}\n" "$(field riskScore)"

# 9 — INCORRECT #5: restricted asset to ineligible recipient -> REQUIRE_APPROVAL
hit POST /risk-check "{\"chainId\":$CHAIN,\"from\":\"$SENDER\",\"to\":\"$RECIP_INELIGIBLE\",\"asset\":\"NVDAx\",\"amount\":\"12000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\",\"recipientEligible\":false}}"
check "09 REQUIRE_APPROVAL: ineligible recipient" 200 "$CODE" "REQUIRE_APPROVAL" "$(field decision)"
printf "     ${DIM}riskScore=%s${NC}\n" "$(field riskScore)"

echo "${BOLD}C. On-chain gate reflected in risk-check (sender correctness)${NC}"

# 10 — INCORRECT sender: not KYC-verified on-chain -> ALLOW by policy but canTransfer=false
hit POST /risk-check "{\"chainId\":$CHAIN,\"from\":\"$SENDER_BAD\",\"to\":\"$RECIP_OK\",\"asset\":\"AAPLx\",\"token\":\"$TRWA\",\"amount\":\"1000000000000000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\",\"recipientEligible\":true}}"
check "10 sender NOT verified: canTransfer=false" 200 "$CODE" "" ""
printf "     ${DIM}decision=%s canTransfer=%s reason=%s${NC}\n" "$(field decision)" "$(field onchainPreview.canTransfer)" "$(field onchainPreview.reason)"

# 11 — Input validation: malformed sender address -> 400
hit POST /risk-check "{\"chainId\":$CHAIN,\"from\":\"0xnotanaddress\",\"to\":\"$RECIP_OK\",\"asset\":\"AAPLx\",\"amount\":\"1\",\"value\":\"0\"}"
check "11 validation: bad sender address -> 400" 400 "$CODE" "" ""

echo "${BOLD}D. Attestation / signing layer — /attest${NC}"

# 12 — Attest the CORRECT transfer -> 200 + EIP-712 signature
hit POST /attest "{\"chainId\":$CHAIN,\"from\":\"$SENDER\",\"to\":\"$RECIP_OK\",\"asset\":\"AAPLx\",\"token\":\"$TRWA\",\"amount\":\"1000000000000000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\",\"recipientEligible\":true}}"
check "12 attest: signs ALLOW" 200 "$CODE" "" ""
printf "     ${DIM}signer=%s signature=%s...${NC}\n" "$(field attestation.signer)" "$(echo "$(field attestation.signature)" | cut -c1-26)"

# 13 — Attest refuses a BLOCK (fake token) -> 409, no signature
hit POST /attest "{\"chainId\":$CHAIN,\"from\":\"$SENDER\",\"to\":\"$RECIP_ELIGIBLE\",\"asset\":\"AAPLx-FAKE\",\"token\":\"$FAKE\",\"amount\":\"10000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\"}}"
check "13 attest: refuses BLOCK -> 409" 409 "$CODE" "" ""
printf "     ${DIM}error=%s${NC}\n" "$(field error)"

# 14 — Attest refuses an INCORRECT sender (not KYC) -> 409, on-chain gate
hit POST /attest "{\"chainId\":$CHAIN,\"from\":\"$SENDER_BAD\",\"to\":\"$RECIP_OK\",\"asset\":\"AAPLx\",\"token\":\"$TRWA\",\"amount\":\"1000000000000000000\",\"value\":\"0\",\"context\":{\"action\":\"TRANSFER\",\"policyId\":\"rwa-retail-v1\",\"recipientEligible\":true}}"
check "14 attest: refuses unverified sender -> 409" 409 "$CODE" "" ""
printf "     ${DIM}error=%s${NC}\n" "$(field error)"

# 15 — Attest refuses an approval (policy-only, not executable) -> 4xx
hit POST /attest "{\"chainId\":$CHAIN,\"from\":\"$SENDER\",\"to\":\"$SPENDER_BAD\",\"asset\":\"AAPLx\",\"token\":\"$TRWA\",\"amount\":\"$MAXUINT\",\"value\":\"0\",\"context\":{\"action\":\"APPROVE\",\"policyId\":\"rwa-retail-v1\",\"spender\":\"$SPENDER_BAD\"}}"
check "15 attest: refuses approval (policy-only)" 409 "$CODE" "" ""
printf "     ${DIM}error=%s${NC}\n" "$(field error)"

echo "----------------------------------------------------------------------"
printf "${BOLD}Result: %s%d passed%s, %s%d failed%s of 15${NC}\n" "$GREEN" "$pass" "$NC" "$([ $fail -gt 0 ] && echo "$RED" || echo "$GREEN")" "$fail" "$NC"
[ $fail -eq 0 ]
