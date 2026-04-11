#!/usr/bin/env bash
#
# seed-challenges.sh — propose and activate the math challenge against a
# live deployment (Sepolia, Anvil, or any EVM RPC).
#
# Assumes scripts/deploy-sepolia.sh has already produced
# deployments/base-sepolia.json AND that the deployer still holds the
# governance role of ChallengeRegistry (i.e. deploy was run with
# SKIP_GOV_TRANSFER=1). On mainnet this path is replaced by a real
# Governance.propose → vote → execute flow.
#
# Environment variables:
#   PRIVATE_KEY  - deployer key (still holds governance)
#   RPC_URL      - target RPC
#   DEPLOYMENT   - optional path to deployment JSON
#                  (default: deployments/base-sepolia.json)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

: "${PRIVATE_KEY:?set PRIVATE_KEY in env}"
: "${RPC_URL:?set RPC_URL in env}"

DEPLOYMENT="${DEPLOYMENT:-$ROOT/deployments/base-sepolia.json}"
if [ ! -f "$DEPLOYMENT" ]; then
  echo "[err] no deployment JSON at $DEPLOYMENT" >&2
  echo "      run scripts/deploy-sepolia.sh first" >&2
  exit 1
fi

# Parse addresses from JSON (no jq dep — use python since it's on every mac)
parse() {
  python3 -c "import json; print(json.load(open('$DEPLOYMENT'))['contracts']['$1'])"
}

TOKEN=$(parse SKRToken)
REGISTRY=$(parse ChallengeRegistry)
VERIFIER=$(parse MathVerifier)

if [ "$VERIFIER" = "pending" ] || [ "$VERIFIER" = "0x0000000000000000000000000000000000000000" ]; then
  echo "[err] MathVerifier not set in deployment JSON" >&2
  echo "      deploy MathVerifierAdapter first and re-run deploy-sepolia.sh" >&2
  echo "      with MATH_VERIFIER=<adapter-address>" >&2
  exit 1
fi

# APPLIED_MATH enum ordinal = 2 (ALGO=0, FORMAL_VER=1, APPLIED_MATH=2, SEC_CODE=3)
DOMAIN=2
SPEC_CID="${SPEC_CID:-0x$(printf 'math-spec-v0%.0s' {1..4} | od -An -tx1 | tr -d ' \n' | cut -c1-64)}"
CIRCUIT_HASH="${CIRCUIT_HASH:-0x$(printf 'math-circuit-hash-v0%.0s' {1..3} | od -An -tx1 | tr -d ' \n' | cut -c1-64)}"
SIGNAL_WEIGHT="${SIGNAL_WEIGHT:-1000000000000000000000}"  # 1000 ether

echo "[..] approving registry bond"
cast send "$TOKEN" \
  "approve(address,uint256)" "$REGISTRY" \
  "$(cast max-uint 256 2>/dev/null || echo 115792089237316195423570985008687907853269984665640564039457584007913129639935)" \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

echo "[..] proposing math challenge"
CHALLENGE_ID_HEX=$(cast send "$REGISTRY" \
  "propose(uint8,address,bytes32,bytes32,uint256)" \
  $DOMAIN "$VERIFIER" "$SPEC_CID" "$CIRCUIT_HASH" "$SIGNAL_WEIGHT" \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" \
  --json | python3 -c "import json, sys; r = json.load(sys.stdin); print(r.get('logs', [{}])[0].get('topics', ['', '0x0'])[1] if r.get('logs') else '0x0')")

# Fallback: read nextChallengeId - 1 if we couldn't parse the event topic
CHALLENGE_ID=$((CHALLENGE_ID_HEX))
if [ "$CHALLENGE_ID" = "0" ]; then
  NEXT=$(cast call "$REGISTRY" "nextChallengeId()(uint256)" --rpc-url "$RPC_URL")
  CHALLENGE_ID=$((NEXT - 1))
fi
echo "[ok] proposed challenge id=$CHALLENGE_ID"

echo "[..] activating challenge $CHALLENGE_ID (requires deployer == governance)"
cast send "$REGISTRY" \
  "activate(uint256)" "$CHALLENGE_ID" \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

STATUS=$(cast call "$REGISTRY" "isActive(uint256)(bool)" "$CHALLENGE_ID" --rpc-url "$RPC_URL")
echo "[ok] challenge $CHALLENGE_ID active=$STATUS"

# Sync the active challenge id to the app env
APP_ENV="$ROOT/app/.env.local"
if [ -f "$APP_ENV" ]; then
  # Remove any existing line, then append
  grep -v "^NEXT_PUBLIC_ACTIVE_CHALLENGE_ID=" "$APP_ENV" > "$APP_ENV.tmp" || true
  echo "NEXT_PUBLIC_ACTIVE_CHALLENGE_ID=$CHALLENGE_ID" >> "$APP_ENV.tmp"
  mv "$APP_ENV.tmp" "$APP_ENV"
  echo "[ok] updated $APP_ENV with active challenge id"
fi
