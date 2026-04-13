#!/usr/bin/env bash
#
# deploy-sepolia.sh — idempotent Base Sepolia deployment for SkillRoot v0
#
# Deploys core contracts (via Deploy.s.sol) plus MathGroth16Verifier and
# MathVerifierAdapter in one shot. Writes deployment JSON and syncs
# addresses to the frontend env.
#
# Usage:
#   cp .env.example .env   # fill in PRIVATE_KEY
#   ./scripts/deploy-sepolia.sh
#
# Idempotent: if deployments/base-sepolia.json exists with live bytecode
# at the token address, the script prints existing addresses and exits 0.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CONTRACTS="$ROOT/contracts"
DEPLOYMENTS="$ROOT/deployments"
OUT_FILE="$DEPLOYMENTS/base-sepolia.json"

# ── Single .env at project root ─────────────────────────────────────────
[ -f "$ROOT/.env" ] && { set -a; source "$ROOT/.env"; set +a; }

: "${PRIVATE_KEY:?set PRIVATE_KEY in .env}"
: "${BASE_SEPOLIA_RPC_URL:?set BASE_SEPOLIA_RPC_URL in .env}"
export PRIVATE_KEY  # forge script reads vm.envUint("PRIVATE_KEY")

RPC="$BASE_SEPOLIA_RPC_URL"
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)

echo "[info] deployer : $DEPLOYER"
echo "[info] rpc      : $RPC"
echo "[info] chain    : Base Sepolia (84532)"

# ── Idempotency check ──────────────────────────────────────────────────
if [ -f "$OUT_FILE" ]; then
  EXISTING=$(python3 -c "
import json
try:
    d = json.load(open('$OUT_FILE'))
    print(d['contracts']['SKRToken'])
except Exception:
    print('')
" 2>/dev/null)
  if [ -n "$EXISTING" ] && [ "$EXISTING" != "" ] && [ "$EXISTING" != "pending" ]; then
    CODE=$(cast code "$EXISTING" --rpc-url "$RPC" 2>/dev/null || echo "0x")
    if [ "$CODE" != "0x" ] && [ "${#CODE}" -gt 4 ]; then
      echo "[ok] contracts already live — skipping redeploy"
      python3 -c "import json; [print(f'  {k:24s} {v}') for k,v in json.load(open('$OUT_FILE'))['contracts'].items()]"
      exit 0
    fi
  fi
  echo "[info] stale deployment detected — redeploying"
fi

mkdir -p "$DEPLOYMENTS"

# ── Step 1: Core contracts via Deploy.s.sol ─────────────────────────────
echo
echo "═══ [1/3] Core contracts (Deploy.s.sol) ═══"
cd "$CONTRACTS"

SKIP_GOV_TRANSFER=1 forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC" \
  --broadcast \
  --slow \
  2>&1 | tee /tmp/skillroot-deploy.log

BROADCAST="$CONTRACTS/broadcast/Deploy.s.sol/84532/run-latest.json"
if [ ! -f "$BROADCAST" ]; then
  echo "[err] broadcast JSON not found at $BROADCAST" >&2
  echo "      check /tmp/skillroot-deploy.log for errors" >&2
  exit 1
fi

addr_of() {
  python3 -c "
import json
for tx in json.load(open('$BROADCAST'))['transactions']:
    if tx.get('transactionType') == 'CREATE' and tx.get('contractName') == '$1':
        print(tx['contractAddress']); break
else:
    raise SystemExit(f'contract $1 not found in broadcast')
"
}

TOKEN=$(addr_of SKRToken)
GOVERNANCE=$(addr_of Governance)
VAULT=$(addr_of StakingVault)
REGISTRY=$(addr_of ChallengeRegistry)
SORTITION=$(addr_of Sortition)
STORE=$(addr_of AttestationStore)
ENGINE=$(addr_of AttestationEngine)
GATEWAY=$(addr_of QueryGateway)

echo
echo "  SKRToken           $TOKEN"
echo "  Governance         $GOVERNANCE"
echo "  StakingVault       $VAULT"
echo "  ChallengeRegistry  $REGISTRY"
echo "  Sortition          $SORTITION"
echo "  AttestationStore   $STORE"
echo "  AttestationEngine  $ENGINE"
echo "  QueryGateway       $GATEWAY"

# ── Step 2: MathGroth16Verifier + Adapter ───────────────────────────────
echo
echo "═══ [2/3] MathGroth16Verifier + MathVerifierAdapter ═══"

deploy_create() {
  local CONTRACT="$1"; shift
  local OUT
  if [ $# -gt 0 ]; then
    OUT=$(forge create "$CONTRACT" \
      --rpc-url "$RPC" \
      --private-key "$PRIVATE_KEY" \
      --broadcast \
      --constructor-args "$@" 2>&1)
  else
    OUT=$(forge create "$CONTRACT" \
      --rpc-url "$RPC" \
      --private-key "$PRIVATE_KEY" \
      --broadcast 2>&1)
  fi
  echo "$OUT" | grep -oE "Deployed to: 0x[a-fA-F0-9]{40}" | awk '{print $3}'
}

MATH_GROTH16=$(deploy_create "src/verifiers/MathVerifier.sol:MathGroth16Verifier")
echo "  MathGroth16Verifier  $MATH_GROTH16"

MATH_ADAPTER=$(deploy_create "src/verifiers/MathVerifierAdapter.sol:MathVerifierAdapter" "$MATH_GROTH16")
echo "  MathVerifierAdapter  $MATH_ADAPTER"

# ── Step 3: Write artifacts ─────────────────────────────────────────────
echo
echo "═══ [3/3] Writing deployment artifacts ═══"

cat > "$OUT_FILE" <<JSON
{
  "chain": "base-sepolia",
  "chainId": 84532,
  "deployedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$DEPLOYER",
  "contracts": {
    "SKRToken":            "$TOKEN",
    "Governance":          "$GOVERNANCE",
    "StakingVault":        "$VAULT",
    "ChallengeRegistry":   "$REGISTRY",
    "Sortition":           "$SORTITION",
    "AttestationStore":    "$STORE",
    "AttestationEngine":   "$ENGINE",
    "QueryGateway":        "$GATEWAY",
    "MathGroth16Verifier": "$MATH_GROTH16",
    "MathVerifierAdapter": "$MATH_ADAPTER"
  },
  "notes": "Governance role held by deployer. Run seed-challenges.sh next."
}
JSON
echo "[ok] $OUT_FILE"

APP_ENV="$ROOT/app/.env.local"
cat > "$APP_ENV" <<EOF
# Auto-generated by deploy-sepolia.sh — $(date -u +%Y-%m-%dT%H:%M:%SZ)
NEXT_PUBLIC_CHAIN_ID=84532
NEXT_PUBLIC_SKR_TOKEN=$TOKEN
NEXT_PUBLIC_GOVERNANCE=$GOVERNANCE
NEXT_PUBLIC_STAKING_VAULT=$VAULT
NEXT_PUBLIC_CHALLENGE_REGISTRY=$REGISTRY
NEXT_PUBLIC_SORTITION=$SORTITION
NEXT_PUBLIC_ATTESTATION_STORE=$STORE
NEXT_PUBLIC_ATTESTATION_ENGINE=$ENGINE
NEXT_PUBLIC_QUERY_GATEWAY=$GATEWAY
NEXT_PUBLIC_MATH_VERIFIER=$MATH_ADAPTER
NEXT_PUBLIC_ACTIVE_CHALLENGE_ID=
NEXT_PUBLIC_WC_PROJECT_ID=${WC_PROJECT_ID:-}
EOF
echo "[ok] $APP_ENV"

# ── Optional: Basescan verification ─────────────────────────────────────
if [ -n "${BASESCAN_API_KEY:-}" ]; then
  echo
  echo "[..] verifying on Basescan (non-blocking)"
  for pair in \
    "src/verifiers/MathVerifier.sol:MathGroth16Verifier $MATH_GROTH16" \
    "src/verifiers/MathVerifierAdapter.sol:MathVerifierAdapter $MATH_ADAPTER"; do
    CONTRACT_PATH=$(echo "$pair" | awk '{print $1}')
    ADDR=$(echo "$pair" | awk '{print $2}')
    forge verify-contract "$ADDR" "$CONTRACT_PATH" \
      --chain 84532 \
      --etherscan-api-key "$BASESCAN_API_KEY" \
      2>/dev/null || echo "  [warn] verify failed for $CONTRACT_PATH — retry manually"
  done
fi

echo
echo "════════════════════════════════════════════════════"
echo "  SkillRoot v0 deployed to Base Sepolia"
echo "  next → ./scripts/seed-challenges.sh"
echo "════════════════════════════════════════════════════"
