#!/usr/bin/env bash
#
# seed-challenges.sh — propose + activate the single modexp math challenge
#
# Requires deploy-sepolia.sh to have run first (produces base-sepolia.json).
#
# Usage:
#   ./scripts/seed-challenges.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# ── Single .env at project root ─────────────────────────────────────────
[ -f "$ROOT/.env" ] && { set -a; source "$ROOT/.env"; set +a; }

: "${PRIVATE_KEY:?set PRIVATE_KEY in .env}"
: "${BASE_SEPOLIA_RPC_URL:?set BASE_SEPOLIA_RPC_URL in .env}"

RPC="$BASE_SEPOLIA_RPC_URL"

DEPLOYMENT="$ROOT/deployments/base-sepolia.json"
if [ ! -f "$DEPLOYMENT" ]; then
  echo "[err] no deployment JSON at $DEPLOYMENT" >&2
  echo "      run scripts/deploy-sepolia.sh first" >&2
  exit 1
fi

parse() {
  python3 -c "import json; print(json.load(open('$DEPLOYMENT'))['contracts']['$1'])"
}

TOKEN=$(parse SKRToken)
REGISTRY=$(parse ChallengeRegistry)
VERIFIER=$(parse MathVerifierAdapter)

if [ -z "$VERIFIER" ] || [ "$VERIFIER" = "pending" ] || [ "$VERIFIER" = "0x0000000000000000000000000000000000000000" ]; then
  echo "[err] MathVerifierAdapter not set in $DEPLOYMENT" >&2
  echo "      re-run deploy-sepolia.sh" >&2
  exit 1
fi

# ── Idempotency: check if challenge 1 already active ───────────────────
ALREADY_ACTIVE=$(cast call "$REGISTRY" "isActive(uint256)(bool)" 1 --rpc-url "$RPC" 2>/dev/null || echo "false")
if [ "$ALREADY_ACTIVE" = "true" ]; then
  echo "[ok] challenge 1 already active — skipping"
  exit 0
fi

# ── Challenge parameters ────────────────────────────────────────────────
# APPLIED_MATH = 2  (ALGO=0, FORMAL_VER=1, APPLIED_MATH=2, SEC_CODE=3)
DOMAIN=2
SPEC_CID="${SPEC_CID:-$(cast keccak "skillroot-math-modexp-v0")}"
CIRCUIT_HASH="${CIRCUIT_HASH:-$(cast keccak "math-circuit-v0")}"
SIGNAL_WEIGHT="${SIGNAL_WEIGHT:-1000000000000000000000}"  # 1000e18

echo "[info] registry : $REGISTRY"
echo "[info] verifier : $VERIFIER"
echo "[info] specCID  : $SPEC_CID"
echo "[info] circuit  : $CIRCUIT_HASH"

# ── Step 1: Approve bond (10,000 SKR) ──────────────────────────────────
echo
echo "[1/3] approving 10,000 SKR proposer bond"
cast send "$TOKEN" \
  "approve(address,uint256)" "$REGISTRY" \
  "$(cast max-uint)" \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY" \
  --confirmations 1 >/dev/null
echo "  approved"

# ── Step 2: Propose challenge ──────────────────────────────────────────
echo
echo "[2/3] proposing modexp challenge (APPLIED_MATH)"
cast send "$REGISTRY" \
  "propose(uint8,address,bytes32,bytes32,uint256)" \
  "$DOMAIN" "$VERIFIER" "$SPEC_CID" "$CIRCUIT_HASH" "$SIGNAL_WEIGHT" \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY" \
  --confirmations 1 >/dev/null

NEXT=$(cast call "$REGISTRY" "nextChallengeId()(uint256)" --rpc-url "$RPC")
CHALLENGE_ID=$((NEXT - 1))
echo "  proposed challenge id=$CHALLENGE_ID"

# ── Step 3: Activate (deployer == governance) ──────────────────────────
echo
echo "[3/3] activating challenge $CHALLENGE_ID"
cast send "$REGISTRY" \
  "activate(uint256)" "$CHALLENGE_ID" \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY" \
  --confirmations 1 >/dev/null

sleep 2
STATUS=$(cast call "$REGISTRY" "isActive(uint256)(bool)" "$CHALLENGE_ID" --rpc-url "$RPC")
if [ "$STATUS" != "true" ]; then
  echo "[err] challenge $CHALLENGE_ID not active after activate() call" >&2
  exit 1
fi
echo "  active=true"

# ── Sync to frontend ──────────────────────────────────────────────────
APP_ENV="$ROOT/app/.env.local"
if [ -f "$APP_ENV" ]; then
  grep -v "^NEXT_PUBLIC_ACTIVE_CHALLENGE_ID=" "$APP_ENV" > "$APP_ENV.tmp" || true
  echo "NEXT_PUBLIC_ACTIVE_CHALLENGE_ID=$CHALLENGE_ID" >> "$APP_ENV.tmp"
  mv "$APP_ENV.tmp" "$APP_ENV"
  echo "[ok] wrote NEXT_PUBLIC_ACTIVE_CHALLENGE_ID=$CHALLENGE_ID → $APP_ENV"
fi

echo
echo "════════════════════════════════════════════════════"
echo "  Math challenge #$CHALLENGE_ID seeded and ACTIVE"
echo "  next → fund a wallet, stake, solve, submit"
echo "════════════════════════════════════════════════════"
