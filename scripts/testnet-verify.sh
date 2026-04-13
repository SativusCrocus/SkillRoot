#!/usr/bin/env bash
#
# testnet-verify.sh — post-deploy checklist for SkillRoot v0 on Base Sepolia
#
# Usage:
#   ./scripts/testnet-verify.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# ── Single .env at project root ─────────────────────────────────────────
[ -f "$ROOT/.env" ] && { set -a; source "$ROOT/.env"; set +a; }

: "${BASE_SEPOLIA_RPC_URL:?set BASE_SEPOLIA_RPC_URL in .env}"
RPC="$BASE_SEPOLIA_RPC_URL"

DEPLOY="$ROOT/deployments/base-sepolia.json"
APP_ENV="$ROOT/app/.env.local"

PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
warn() { WARN=$((WARN + 1)); echo "  ! $1"; }

parse() {
  python3 -c "import json; print(json.load(open('$DEPLOY'))['contracts']['$1'])"
}

# ════════════════════════════════════════════════════════════════════════
echo "═══ 1/5  Deployment JSON ═══"
# ════════════════════════════════════════════════════════════════════════

if [ ! -f "$DEPLOY" ]; then
  fail "deployments/base-sepolia.json missing"
  echo "     run: ./scripts/deploy-sepolia.sh"
  exit 1
fi
pass "deployments/base-sepolia.json exists"

CHAIN_ID=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['chainId'])")
if [ "$CHAIN_ID" = "84532" ]; then
  pass "chainId = 84532 (Base Sepolia)"
else
  fail "chainId = $CHAIN_ID (expected 84532)"
fi

for NAME in SKRToken Governance StakingVault ChallengeRegistry Sortition AttestationStore AttestationEngine QueryGateway MathGroth16Verifier MathVerifierAdapter; do
  ADDR=$(parse "$NAME")
  if [ -z "$ADDR" ] || [ "$ADDR" = "" ] || [ "$ADDR" = "pending" ]; then
    fail "$NAME address missing"
  else
    pass "$NAME = $ADDR"
  fi
done

# ════════════════════════════════════════════════════════════════════════
echo
echo "═══ 2/5  Contracts live on-chain ═══"
# ════════════════════════════════════════════════════════════════════════

for NAME in SKRToken Governance StakingVault ChallengeRegistry Sortition AttestationStore AttestationEngine QueryGateway MathGroth16Verifier MathVerifierAdapter; do
  ADDR=$(parse "$NAME")
  CODE=$(cast code "$ADDR" --rpc-url "$RPC" 2>/dev/null || echo "0x")
  if [ "$CODE" != "0x" ] && [ "${#CODE}" -gt 4 ]; then
    pass "$NAME has bytecode"
  else
    fail "$NAME at $ADDR has no bytecode"
  fi
done

# ════════════════════════════════════════════════════════════════════════
echo
echo "═══ 3/5  Challenge seeded ═══"
# ════════════════════════════════════════════════════════════════════════

REGISTRY=$(parse ChallengeRegistry)
NEXT_ID=$(cast call "$REGISTRY" "nextChallengeId()(uint256)" --rpc-url "$RPC" 2>/dev/null || echo "1")

if [ "$NEXT_ID" -gt 1 ] 2>/dev/null; then
  pass "nextChallengeId = $NEXT_ID (challenges proposed)"
else
  fail "no challenges proposed (nextChallengeId = $NEXT_ID)"
fi

ACTIVE=$(cast call "$REGISTRY" "isActive(uint256)(bool)" 1 --rpc-url "$RPC" 2>/dev/null || echo "false")
if [ "$ACTIVE" = "true" ]; then
  pass "challenge 1 is ACTIVE"
else
  fail "challenge 1 is not active"
fi

# ════════════════════════════════════════════════════════════════════════
echo
echo "═══ 4/5  Frontend env ═══"
# ════════════════════════════════════════════════════════════════════════

if [ ! -f "$APP_ENV" ]; then
  fail "app/.env.local missing"
else
  pass "app/.env.local exists"

  check_env() {
    local KEY="$1"
    local EXPECTED="$2"
    local VAL
    VAL=$(grep "^${KEY}=" "$APP_ENV" 2>/dev/null | head -1 | cut -d'=' -f2-)
    if [ -z "$VAL" ]; then
      fail "$KEY not set in app/.env.local"
    elif [ -n "$EXPECTED" ]; then
      VAL_LOWER=$(echo "$VAL" | tr '[:upper:]' '[:lower:]')
      EXP_LOWER=$(echo "$EXPECTED" | tr '[:upper:]' '[:lower:]')
      if [ "$VAL_LOWER" = "$EXP_LOWER" ]; then
        pass "$KEY matches deployment"
      else
        fail "$KEY mismatch: env=$VAL deploy=$EXPECTED"
      fi
    else
      pass "$KEY is set"
    fi
  }

  check_env "NEXT_PUBLIC_CHAIN_ID" "84532"
  check_env "NEXT_PUBLIC_SKR_TOKEN" "$(parse SKRToken)"
  check_env "NEXT_PUBLIC_GOVERNANCE" "$(parse Governance)"
  check_env "NEXT_PUBLIC_STAKING_VAULT" "$(parse StakingVault)"
  check_env "NEXT_PUBLIC_CHALLENGE_REGISTRY" "$(parse ChallengeRegistry)"
  check_env "NEXT_PUBLIC_ATTESTATION_ENGINE" "$(parse AttestationEngine)"
  check_env "NEXT_PUBLIC_QUERY_GATEWAY" "$(parse QueryGateway)"
  check_env "NEXT_PUBLIC_MATH_VERIFIER" "$(parse MathVerifierAdapter)"
fi

# ════════════════════════════════════════════════════════════════════════
echo
echo "═══ 5/5  First attestation ═══"
# ════════════════════════════════════════════════════════════════════════

ENGINE=$(parse AttestationEngine)
GATEWAY=$(parse QueryGateway)

NEXT_CLAIM=$(cast call "$ENGINE" "nextClaimId()(uint256)" --rpc-url "$RPC" 2>/dev/null || echo "1")
if [ "$NEXT_CLAIM" -gt 1 ] 2>/dev/null; then
  pass "claims submitted (nextClaimId = $NEXT_CLAIM)"

  STATUS=$(cast call "$ENGINE" "claimStatus(uint256)(uint8)" 1 --rpc-url "$RPC" 2>/dev/null || echo "")
  case "$STATUS" in
    0) warn "claim 1 status = SUBMITTED (awaiting committee draw)" ;;
    1) warn "claim 1 status = COMMITTEE_DRAWN (awaiting votes/finalize)" ;;
    2) warn "claim 1 status = EXPIRED" ;;
    3) pass "claim 1 status = FINALIZED_ACCEPT" ;;
    4) fail "claim 1 status = FINALIZED_REJECT" ;;
    *) warn "claim 1 status = $STATUS (unknown)" ;;
  esac

  DEPLOYER_ADDR=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['deployer'])" 2>/dev/null || echo "")
  if [ -n "$DEPLOYER_ADDR" ]; then
    SCORES=$(cast call "$GATEWAY" "verify(address)(uint256[4])" "$DEPLOYER_ADDR" --rpc-url "$RPC" 2>/dev/null || echo "")
    if [ -n "$SCORES" ]; then
      echo "  deployer scores: $SCORES"
    fi
  fi
else
  warn "no claims submitted yet (run the first-attestation guide)"
fi

# ════════════════════════════════════════════════════════════════════════
echo
echo "════════════════════════════════════════════════════"
echo "  PASS=$PASS  FAIL=$FAIL  WARN=$WARN"
if [ "$FAIL" -eq 0 ]; then
  echo "  All checks passed."
else
  echo "  $FAIL check(s) failed — review above."
fi
echo "════════════════════════════════════════════════════"

exit "$FAIL"
