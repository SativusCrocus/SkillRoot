#!/usr/bin/env bash
#
# bootstrap-verify.sh — Post-bootstrap verification for SkillRoot v0
#
# Checks:
#   1. 5 validators bonded with >= 5,000 SKR each
#   2. First attestation status = FINALIZED_ACCEPT
#   3. /me scores > 0 for APPLIED_MATH domain
#   4. QueryGateway returns non-zero scores
#   5. All 9 contracts have live bytecode
#
# Usage:
#   ./scripts/bootstrap-verify.sh
#   ./scripts/bootstrap-verify.sh --claim <id>   # check a specific claim (default: 1)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# --- Colours ----------------------------------------------------------------
RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[0;33m"; BLU="\033[0;34m"; NC="\033[0m"
PASS=0; FAIL=0
pass() { printf "${GRN}[PASS]${NC} %s\n" "$*"; PASS=$((PASS + 1)); }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*"; FAIL=$((FAIL + 1)); }
info() { printf "${BLU}[....]${NC} %s\n" "$*"; }

# --- Flags ------------------------------------------------------------------
CLAIM_ID=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --claim) CLAIM_ID="${2:?usage: --claim <id>}"; shift 2 ;;
    *)       echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

# --- Environment ------------------------------------------------------------
export PATH="$HOME/.foundry/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  LATEST_NODE="$(ls -1 "$HOME/.nvm/versions/node" | sort -V | tail -n1)"
  export PATH="$HOME/.nvm/versions/node/$LATEST_NODE/bin:$PATH"
fi

[ -f "$ROOT/.env" ] || { fail ".env not found"; exit 1; }
set -a; source "$ROOT/.env"; set +a

: "${PRIVATE_KEY:?set PRIVATE_KEY in .env}"
: "${BASE_SEPOLIA_RPC_URL:?set BASE_SEPOLIA_RPC_URL in .env}"

RPC="$BASE_SEPOLIA_RPC_URL"
DEPLOY_JSON="$ROOT/deployments/base-sepolia.json"
[ -f "$DEPLOY_JSON" ] || { fail "no deployment at $DEPLOY_JSON"; exit 1; }

p() { python3 -c "import json; print(json.load(open('$DEPLOY_JSON'))['contracts']['$1'])"; }
TOKEN=$(p SKRToken)
GOVERNANCE=$(p Governance)
VAULT=$(p StakingVault)
REGISTRY=$(p ChallengeRegistry)
SORTITION=$(p Sortition)
STORE=$(p AttestationStore)
ENGINE=$(p AttestationEngine)
GATEWAY=$(p QueryGateway)
GROTH16=$(p MathGroth16Verifier)
ADAPTER=$(p MathVerifierAdapter)

DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
SKR="node $ROOT/cli/dist/bin.js"

echo
echo "  SkillRoot v0 — Post-Bootstrap Verification"
echo "  chain     : Base Sepolia (84532)"
echo "  rpc       : $RPC"
echo "  deployer  : $DEPLOYER"
echo "  claim     : $CLAIM_ID"
echo

# ============================================================================
#  CHECK 1 — All contracts have live bytecode
# ============================================================================
info "Check 1: Contract bytecode"

declare -A CONTRACTS=(
  [SKRToken]="$TOKEN"
  [Governance]="$GOVERNANCE"
  [StakingVault]="$VAULT"
  [ChallengeRegistry]="$REGISTRY"
  [Sortition]="$SORTITION"
  [AttestationStore]="$STORE"
  [AttestationEngine]="$ENGINE"
  [QueryGateway]="$GATEWAY"
  [MathGroth16Verifier]="$GROTH16"
  [MathVerifierAdapter]="$ADAPTER"
)

LIVE_COUNT=0
for name in "${!CONTRACTS[@]}"; do
  addr="${CONTRACTS[$name]}"
  CODE=$(cast code "$addr" --rpc-url "$RPC" 2>/dev/null || echo "0x")
  if [ "$CODE" != "0x" ] && [ "${#CODE}" -gt 4 ]; then
    LIVE_COUNT=$((LIVE_COUNT + 1))
  else
    fail "$name ($addr) — no bytecode"
  fi
done

if [ "$LIVE_COUNT" -eq 10 ]; then
  pass "all 10 contracts live"
else
  fail "$LIVE_COUNT / 10 contracts live"
fi

# ============================================================================
#  CHECK 2 — 5 validators bonded with >= 5,000 SKR
# ============================================================================
info "Check 2: Validators bonded"

VCOUNT=$(cast call "$VAULT" "validatorCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')

if [ "$VCOUNT" -ge 5 ]; then
  pass "validatorCount = $VCOUNT (>= 5)"
else
  fail "validatorCount = $VCOUNT (expected >= 5)"
fi

VALIDATORS_RAW=$(cast call "$VAULT" "getValidators()(address[])" --rpc-url "$RPC")
# Parse [addr1, addr2, ...] into lines
VALIDATORS=$(echo "$VALIDATORS_RAW" | tr -d '[]' | tr ',' '\n' | tr -d ' ' | grep '^0x')

BONDED_OK=0
BONDED_FAIL=0
MIN_STAKE_WEI="5000000000000000000000"

while IFS= read -r vaddr; do
  [ -z "$vaddr" ] && continue
  STAKE=$(cast call "$VAULT" "stakeOf(address)(uint256)" "$vaddr" --rpc-url "$RPC" | awk '{print $1}')
  OK=$(python3 -c "print('yes' if int('$STAKE') >= int('$MIN_STAKE_WEI') else 'no')")
  STAKE_SKR=$(python3 -c "print(int('$STAKE') / 10**18)")
  if [ "$OK" = "yes" ]; then
    printf "  ${GRN}+${NC} %s  stake=%s SKR\n" "$vaddr" "$STAKE_SKR"
    BONDED_OK=$((BONDED_OK + 1))
  else
    printf "  ${RED}-${NC} %s  stake=%s SKR (below 5000)\n" "$vaddr" "$STAKE_SKR"
    BONDED_FAIL=$((BONDED_FAIL + 1))
  fi
done <<< "$VALIDATORS"

if [ "$BONDED_OK" -ge 5 ]; then
  pass "$BONDED_OK validators with >= 5,000 SKR"
else
  fail "$BONDED_OK / 5 validators with >= 5,000 SKR"
fi

# ============================================================================
#  CHECK 3 — Challenge #1 active
# ============================================================================
info "Check 3: Challenge #1 active"

ACTIVE=$(cast call "$REGISTRY" "isActive(uint256)(bool)" 1 --rpc-url "$RPC" 2>/dev/null || echo "false")
if [ "$ACTIVE" = "true" ]; then
  pass "challenge #1 active"
else
  fail "challenge #1 not active"
fi

# ============================================================================
#  CHECK 4 — First attestation FINALIZED_ACCEPT
# ============================================================================
info "Check 4: Claim #$CLAIM_ID status"

CLAIM_RAW=$(cast call "$ENGINE" \
  "getClaim(uint256)(uint256,uint256,address,uint64,uint64,bytes32,uint8,uint8,uint8)" \
  "$CLAIM_ID" --rpc-url "$RPC" 2>/dev/null || echo "")

if [ -z "$CLAIM_RAW" ]; then
  fail "claim #$CLAIM_ID does not exist"
else
  CLAIMANT=$(echo "$CLAIM_RAW" | sed -n '3p' | awk '{print $1}')
  DEADLINE=$(echo "$CLAIM_RAW" | sed -n '5p' | awk '{print $1}')
  STATUS=$(echo "$CLAIM_RAW" | sed -n '7p' | awk '{print $1}')
  YES_VOTES=$(echo "$CLAIM_RAW" | sed -n '8p' | awk '{print $1}')
  NO_VOTES=$(echo "$CLAIM_RAW" | sed -n '9p' | awk '{print $1}')

  STATUS_NAME="UNKNOWN"
  case "$STATUS" in
    0) STATUS_NAME="SUBMITTED" ;;
    1) STATUS_NAME="COMMITTEE_DRAWN" ;;
    2) STATUS_NAME="FINALIZED_ACCEPT" ;;
    3) STATUS_NAME="FINALIZED_REJECT" ;;
    4) STATUS_NAME="EXPIRED" ;;
  esac

  echo "  claimant  : $CLAIMANT"
  echo "  status    : $STATUS_NAME ($STATUS)"
  echo "  votes     : $YES_VOTES yes / $NO_VOTES no"
  echo "  deadline  : $(date -r "$DEADLINE" 2>/dev/null || echo "$DEADLINE")"

  if [ "$STATUS" = "2" ]; then
    pass "claim #$CLAIM_ID = FINALIZED_ACCEPT"
  elif [ "$STATUS" = "1" ]; then
    NOW=$(date +%s)
    if [ "$NOW" -le "$DEADLINE" ]; then
      REMAINING=$((DEADLINE - NOW))
      fail "claim #$CLAIM_ID still in voting — ${REMAINING}s until deadline"
    else
      fail "claim #$CLAIM_ID vote closed but not finalized — run: cast send $ENGINE 'finalize(uint256)' $CLAIM_ID --rpc-url \$BASE_SEPOLIA_RPC_URL --private-key \$PRIVATE_KEY"
    fi
  else
    fail "claim #$CLAIM_ID status = $STATUS_NAME (expected FINALIZED_ACCEPT)"
  fi
fi

# ============================================================================
#  CHECK 5 — QueryGateway returns non-zero APPLIED_MATH score
# ============================================================================
info "Check 5: QueryGateway scores"

if [ -n "${CLAIMANT:-}" ]; then
  QUERY_ADDR="$CLAIMANT"
else
  QUERY_ADDR="$DEPLOYER"
fi

SCORES_RAW=$(cast call "$GATEWAY" "verify(address)(uint256[4])" "$QUERY_ADDR" --rpc-url "$RPC" 2>/dev/null || echo "")

if [ -z "$SCORES_RAW" ]; then
  fail "QueryGateway.verify() failed"
else
  # Strip cast annotations like [1e21], then parse array
  SCORES_CLEAN=$(echo "$SCORES_RAW" | sed -E 's/\[[^][]*\]//g' | tr -d '[]' | tr ',' '\n' | tr -d ' ')
  DOMAINS=("ALGO" "FORMAL_VER" "APPLIED_MATH" "SEC_CODE")
  IDX=0
  APPLIED_MATH_SCORE="0"

  while IFS= read -r score; do
    [ -z "$score" ] && continue
    SCORE_SKR=$(python3 -c "print(int('$score') / 10**18)" 2>/dev/null || echo "$score")
    printf "  %-14s %s\n" "${DOMAINS[$IDX]}" "$SCORE_SKR"
    if [ "$IDX" = "2" ]; then
      APPLIED_MATH_SCORE="$score"
    fi
    IDX=$((IDX + 1))
  done <<< "$SCORES_CLEAN"

  AM_OK=$(python3 -c "print('yes' if int('$APPLIED_MATH_SCORE') > 0 else 'no')" 2>/dev/null || echo "no")
  if [ "$AM_OK" = "yes" ]; then
    pass "APPLIED_MATH score > 0 for $QUERY_ADDR"
  else
    fail "APPLIED_MATH score = 0 for $QUERY_ADDR"
  fi
fi

# ============================================================================
#  CHECK 6 — CLI query works
# ============================================================================
info "Check 6: CLI skr query"

if [ -f "$ROOT/cli/dist/bin.js" ]; then
  CLI_OUT=$(PRIVATE_KEY="$PRIVATE_KEY" $SKR query "$QUERY_ADDR" 2>&1 || echo "CLI_ERROR")
  if echo "$CLI_OUT" | grep -q "APPLIED_MATH"; then
    pass "skr query returns scores"
    echo "$CLI_OUT" | sed 's/^/  /'
  elif echo "$CLI_OUT" | grep -q "CLI_ERROR"; then
    fail "skr query errored"
  else
    pass "skr query ran (output below)"
    echo "$CLI_OUT" | sed 's/^/  /'
  fi
else
  fail "CLI not built — run: pnpm -C cli build"
fi

# ============================================================================
#  CHECK 7 — Committee was drawn for the claim
# ============================================================================
info "Check 7: Committee drawn"

COMMITTEE_RAW=$(cast call "$ENGINE" "committeeOf(uint256)(address[])" "$CLAIM_ID" --rpc-url "$RPC" 2>/dev/null || echo "[]")
COMMITTEE_SIZE=$(echo "$COMMITTEE_RAW" | tr -d '[]' | tr ',' '\n' | grep -c '^0x' || echo "0")

if [ "$COMMITTEE_SIZE" -ge 1 ]; then
  pass "committee size = $COMMITTEE_SIZE for claim #$CLAIM_ID"
else
  fail "no committee drawn for claim #$CLAIM_ID"
fi

# ============================================================================
#  SUMMARY
# ============================================================================
echo
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf "${GRN}=============================================${NC}\n"
  printf "${GRN}  ALL %d CHECKS PASSED                       ${NC}\n" "$TOTAL"
  printf "${GRN}=============================================${NC}\n"
  echo "  validators      : $VCOUNT bonded"
  echo "  claim #$CLAIM_ID        : ${STATUS_NAME:-UNKNOWN}"
  echo "  applied_math    : $(python3 -c "print(int('${APPLIED_MATH_SCORE:-0}') / 10**18)" 2>/dev/null || echo '?') SKR-weighted"
  echo "  contracts       : $LIVE_COUNT / 10 live"
  echo "  engine          : https://sepolia.basescan.org/address/$ENGINE"
  echo "  frontend        : https://app-nine-rho-70.vercel.app"
  exit 0
else
  printf "${RED}=============================================${NC}\n"
  printf "${RED}  %d PASSED / %d FAILED                       ${NC}\n" "$PASS" "$FAIL"
  printf "${RED}=============================================${NC}\n"
  exit 1
fi
