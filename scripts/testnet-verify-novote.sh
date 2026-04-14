#!/usr/bin/env bash
#
# testnet-verify-novote.sh — post-deploy checklist for SkillRoot
# v0.2.0-no-vote on Base Sepolia.
#
# Checks:
#   1. deployments/base-sepolia.json shape + version pin
#   2. every contract has live bytecode
#   3. genesis challenge is ACTIVE and the genesis key is burned
#   4. app/.env.local env keys match deployment
#   5. first claim (if any) and its status (0=PENDING, 1=ACCEPT, 2=REJECT)
#
# Usage:
#   ./scripts/testnet-verify-novote.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

[ -f "$ROOT/.env" ] && { set -a; source "$ROOT/.env"; set +a; }

: "${BASE_SEPOLIA_RPC_URL:?set BASE_SEPOLIA_RPC_URL in .env}"
RPC="$BASE_SEPOLIA_RPC_URL"

DEPLOY="$ROOT/deployments/base-sepolia.json"
APP_ENV="$ROOT/app/.env.local"
EXPECTED_VERSION="v0.2.0-no-vote"

CONTRACT_NAMES=(
  SKRToken
  StakingVault
  AttestationStore
  ChallengeRegistry
  AttestationEngine
  QueryGateway
  MathGroth16Verifier
  MathVerifierAdapter
  FraudGroth16Verifier
  FraudVerifierAdapter
)

PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
warn() { WARN=$((WARN + 1)); echo "  ! $1"; }

parse() {
  python3 -c "import json; print(json.load(open('$DEPLOY'))['contracts'].get('$1',''))"
}

# ════════════════════════════════════════════════════════════════════════
echo "═══ 1/5  Deployment JSON ═══"
# ════════════════════════════════════════════════════════════════════════

if [ ! -f "$DEPLOY" ]; then
  fail "deployments/base-sepolia.json missing"
  echo "     run: ./scripts/deploy-sepolia-novote.sh"
  exit 1
fi
pass "deployments/base-sepolia.json exists"

CHAIN_ID=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['chainId'])")
if [ "$CHAIN_ID" = "84532" ]; then
  pass "chainId = 84532 (Base Sepolia)"
else
  fail "chainId = $CHAIN_ID (expected 84532)"
fi

VERSION=$(python3 -c "import json; print(json.load(open('$DEPLOY')).get('version',''))")
if [ "$VERSION" = "$EXPECTED_VERSION" ]; then
  pass "version = $EXPECTED_VERSION"
else
  fail "version = '$VERSION' (expected $EXPECTED_VERSION)"
fi

for NAME in "${CONTRACT_NAMES[@]}"; do
  ADDR=$(parse "$NAME")
  if [ -z "$ADDR" ]; then
    fail "$NAME address missing"
  else
    pass "$NAME = $ADDR"
  fi
done

# Must NOT contain deleted contracts
for GONE in Governance Sortition ForgeGuard ForgeVerifierAdapter; do
  IF_THERE=$(python3 -c "import json; print('1' if '$GONE' in json.load(open('$DEPLOY'))['contracts'] else '0')")
  if [ "$IF_THERE" = "1" ]; then
    fail "deployment JSON still references deleted contract $GONE"
  else
    pass "deployment JSON has no $GONE entry"
  fi
done

# ════════════════════════════════════════════════════════════════════════
echo
echo "═══ 2/5  Contracts live on-chain ═══"
# ════════════════════════════════════════════════════════════════════════

for NAME in "${CONTRACT_NAMES[@]}"; do
  ADDR=$(parse "$NAME")
  [ -z "$ADDR" ] && continue
  CODE=$(cast code "$ADDR" --rpc-url "$RPC" 2>/dev/null || echo "0x")
  if [ "$CODE" != "0x" ] && [ "${#CODE}" -gt 4 ]; then
    pass "$NAME has bytecode"
  else
    fail "$NAME at $ADDR has no bytecode"
  fi
done

# ════════════════════════════════════════════════════════════════════════
echo
echo "═══ 3/5  Genesis challenge + key burned ═══"
# ════════════════════════════════════════════════════════════════════════

REGISTRY=$(parse ChallengeRegistry)
NEXT_ID=$(cast call "$REGISTRY" "nextChallengeId()(uint256)" --rpc-url "$RPC" 2>/dev/null || echo "1")
if [ "$NEXT_ID" -gt 1 ] 2>/dev/null; then
  pass "nextChallengeId = $NEXT_ID (≥1 proposed)"
else
  fail "no challenges proposed (nextChallengeId = $NEXT_ID)"
fi

ACTIVE=$(cast call "$REGISTRY" "isActive(uint256)(bool)" 1 --rpc-url "$RPC" 2>/dev/null || echo "false")
if [ "$ACTIVE" = "true" ]; then
  pass "challenge 1 is ACTIVE"
else
  fail "challenge 1 is not active"
fi

GENESIS=$(cast call "$REGISTRY" "genesisDeployer()(address)" --rpc-url "$RPC" 2>/dev/null || echo "")
if [ "$(echo "$GENESIS" | tr '[:upper:]' '[:lower:]')" = "0x0000000000000000000000000000000000000000" ]; then
  pass "genesisDeployer burned (0x0)"
else
  fail "genesisDeployer = $GENESIS (expected 0x0 — key not burned)"
fi

# Engine wiring
ENGINE=$(parse AttestationEngine)
VAULT=$(parse StakingVault)
STORE=$(parse AttestationStore)

VAULT_ENGINE=$(cast call "$VAULT" "engine()(address)" --rpc-url "$RPC" 2>/dev/null || echo "")
if [ "$(echo "$VAULT_ENGINE" | tr '[:upper:]' '[:lower:]')" = "$(echo "$ENGINE" | tr '[:upper:]' '[:lower:]')" ]; then
  pass "vault.engine = engine"
else
  fail "vault.engine = $VAULT_ENGINE (expected $ENGINE)"
fi

STORE_ENGINE=$(cast call "$STORE" "engine()(address)" --rpc-url "$RPC" 2>/dev/null || echo "")
if [ "$(echo "$STORE_ENGINE" | tr '[:upper:]' '[:lower:]')" = "$(echo "$ENGINE" | tr '[:upper:]' '[:lower:]')" ]; then
  pass "store.engine = engine"
else
  fail "store.engine = $STORE_ENGINE (expected $ENGINE)"
fi

# Engine must be wired to the fraud verifier adapter
FRAUD_ADAPTER=$(parse FraudVerifierAdapter)
ENGINE_FRAUD=$(cast call "$ENGINE" "fraudVerifier()(address)" --rpc-url "$RPC" 2>/dev/null || echo "")
if [ "$(echo "$ENGINE_FRAUD" | tr '[:upper:]' '[:lower:]')" = "$(echo "$FRAUD_ADAPTER" | tr '[:upper:]' '[:lower:]')" ]; then
  pass "engine.fraudVerifier = FraudVerifierAdapter"
else
  fail "engine.fraudVerifier = $ENGINE_FRAUD (expected $FRAUD_ADAPTER)"
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

  check_env "NEXT_PUBLIC_CHAIN_ID"            "84532"
  check_env "NEXT_PUBLIC_SKR_TOKEN"           "$(parse SKRToken)"
  check_env "NEXT_PUBLIC_STAKING_VAULT"       "$(parse StakingVault)"
  check_env "NEXT_PUBLIC_ATTESTATION_STORE"   "$(parse AttestationStore)"
  check_env "NEXT_PUBLIC_CHALLENGE_REGISTRY"  "$(parse ChallengeRegistry)"
  check_env "NEXT_PUBLIC_ATTESTATION_ENGINE"  "$(parse AttestationEngine)"
  check_env "NEXT_PUBLIC_QUERY_GATEWAY"       "$(parse QueryGateway)"
  check_env "NEXT_PUBLIC_MATH_VERIFIER"       "$(parse MathVerifierAdapter)"
  check_env "NEXT_PUBLIC_FRAUD_VERIFIER"      "$(parse FraudVerifierAdapter)"
  check_env "NEXT_PUBLIC_ACTIVE_CHALLENGE_ID" "1"

  # And must NOT carry stale governance/sortition keys
  for STALE in NEXT_PUBLIC_GOVERNANCE NEXT_PUBLIC_SORTITION; do
    if grep -q "^${STALE}=" "$APP_ENV"; then
      fail "$STALE still present in app/.env.local"
    else
      pass "$STALE absent from app/.env.local"
    fi
  done
fi

# ════════════════════════════════════════════════════════════════════════
echo
echo "═══ 5/5  First claim ═══"
# ════════════════════════════════════════════════════════════════════════

GATEWAY=$(parse QueryGateway)
NEXT_CLAIM=$(cast call "$ENGINE" "nextClaimId()(uint256)" --rpc-url "$RPC" 2>/dev/null || echo "1")

if [ "$NEXT_CLAIM" -gt 1 ] 2>/dev/null; then
  pass "claims submitted (nextClaimId = $NEXT_CLAIM)"

  # getClaim(uint256) returns (uint256,uint256,address,uint64,uint64,uint256,bytes32,uint8)
  CLAIM_TUPLE=$(cast call "$ENGINE" \
    "getClaim(uint256)((uint256,uint256,address,uint64,uint64,uint256,bytes32,uint8))" 1 \
    --rpc-url "$RPC" 2>/dev/null || echo "")
  # Status is the last comma-separated field, trim parens
  STATUS=$(echo "$CLAIM_TUPLE" | tr -d '()' | awk -F',' '{gsub(/ /,"",$NF); print $NF}')
  case "$STATUS" in
    0) warn "claim 1 status = PENDING (challenge window open)" ;;
    1) pass "claim 1 status = FINALIZED_ACCEPT" ;;
    2) fail "claim 1 status = FINALIZED_REJECT (fraud proven)" ;;
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
  warn "no claims submitted yet (submit one through the app or CLI)"
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
