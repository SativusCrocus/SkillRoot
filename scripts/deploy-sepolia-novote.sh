#!/usr/bin/env bash
#
# deploy-sepolia-novote.sh — idempotent Base Sepolia deployment for
# SkillRoot v0.2.0-no-vote (fraud-proof + auto-finalize flow).
#
# Self-contained: uses raw `forge create` per contract rather than a forge
# script, because the v0.2.0 contract graph drops Governance/Sortition/
# ForgeGuard entirely and the old Deploy.s.sol no longer applies.
#
# Deployment order:
#   1. SKRToken(deployer)                      — deployer holds 100M SKR
#   2. StakingVault(token, deployer)           — deployer is governance
#   3. AttestationStore(deployer)              — deployer is governance
#   4. ChallengeRegistry(token, vault)         — deployer is one-shot genesisDeployer
#   5. MathGroth16Verifier
#   6. MathVerifierAdapter(mathGroth16)
#   7. FraudGroth16Verifier                    — from circuits/fraud/build.sh
#   8. FraudVerifierAdapter(fraudGroth16)
#   9. AttestationEngine(registry, vault, store, token, fraudAdapter)
#  10. QueryGateway(store)
# Post-deploy:
#   - vault.setEngine(engine)   (onlyGovernance)
#   - store.setEngine(engine)   (onlyGovernance)
#   - token.approve(registry, PROPOSER_BOND)
#   - registry.propose(APPLIED_MATH, mathAdapter, 0x00, 0x00, 100e18)
#   - registry.genesisActivate(1)   — burns the one-shot key
#
# Usage:
#   cp .env.example .env   # fill PRIVATE_KEY, BASE_SEPOLIA_RPC_URL
#   ./scripts/deploy-sepolia-novote.sh
#
# Idempotent: if deployments/base-sepolia.json reports v0.2.0-no-vote with
# live SKRToken bytecode, the script prints addresses and exits 0.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CONTRACTS="$ROOT/contracts"
DEPLOYMENTS="$ROOT/deployments"
OUT_FILE="$DEPLOYMENTS/base-sepolia.json"
VERSION="v0.2.0-no-vote"

[ -f "$ROOT/.env" ] && { set -a; source "$ROOT/.env"; set +a; }

: "${PRIVATE_KEY:?set PRIVATE_KEY in .env}"
: "${BASE_SEPOLIA_RPC_URL:?set BASE_SEPOLIA_RPC_URL in .env}"
export PRIVATE_KEY

RPC="$BASE_SEPOLIA_RPC_URL"
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)

echo "[info] deployer : $DEPLOYER"
echo "[info] rpc      : $RPC"
echo "[info] chain    : Base Sepolia (84532)"
echo "[info] version  : $VERSION"

# ── Preflight: FraudVerifier.sol must exist ────────────────────────────
FRAUD_SRC="$CONTRACTS/src/verifiers/FraudVerifier.sol"
FRAUD_BUILT="$ROOT/circuits/fraud/build/FraudVerifier.sol"
if [ ! -f "$FRAUD_SRC" ]; then
  if [ -f "$FRAUD_BUILT" ]; then
    cp "$FRAUD_BUILT" "$FRAUD_SRC"
    echo "[ok] copied $FRAUD_BUILT → $FRAUD_SRC"
  else
    echo "[err] $FRAUD_SRC missing and $FRAUD_BUILT not built"
    echo "      run: ./circuits/fraud/build.sh"
    exit 1
  fi
fi

# ── Idempotency check ──────────────────────────────────────────────────
if [ -f "$OUT_FILE" ]; then
  EXISTING_VERSION=$(python3 -c "
import json
try:
    d = json.load(open('$OUT_FILE'))
    print(d.get('version',''))
except Exception:
    print('')
" 2>/dev/null)
  EXISTING=$(python3 -c "
import json
try:
    d = json.load(open('$OUT_FILE'))
    print(d['contracts'].get('SKRToken',''))
except Exception:
    print('')
" 2>/dev/null)
  if [ "$EXISTING_VERSION" = "$VERSION" ] && [ -n "$EXISTING" ]; then
    CODE=$(cast code "$EXISTING" --rpc-url "$RPC" 2>/dev/null || echo "0x")
    if [ "$CODE" != "0x" ] && [ "${#CODE}" -gt 4 ]; then
      echo "[ok] $VERSION contracts already live — skipping redeploy"
      python3 -c "import json; [print(f'  {k:22s} {v}') for k,v in json.load(open('$OUT_FILE'))['contracts'].items()]"
      exit 0
    fi
  fi
  echo "[info] stale or pre-$VERSION deployment detected — redeploying"
fi

mkdir -p "$DEPLOYMENTS"

# ── forge create helper ────────────────────────────────────────────────
cd "$CONTRACTS"
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
  local ADDR
  ADDR=$(echo "$OUT" | grep -oE "Deployed to: 0x[a-fA-F0-9]{40}" | awk '{print $3}')
  if [ -z "$ADDR" ]; then
    echo "[err] forge create failed for $CONTRACT" >&2
    echo "$OUT" >&2
    exit 1
  fi
  # Wait for the next nonce to settle on the RPC (Base Sepolia public RPC lags).
  local DEPLOYER_ADDR
  DEPLOYER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)
  local TARGET_NONCE
  TARGET_NONCE=$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC" 2>/dev/null || echo 0)
  local WAITED=0
  while [ "$WAITED" -lt 30 ]; do
    local CUR
    CUR=$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC" 2>/dev/null || echo 0)
    if [ "$CUR" -ge "$TARGET_NONCE" ] 2>/dev/null; then
      break
    fi
    sleep 1
    WAITED=$((WAITED + 1))
  done
  sleep 2
  echo "$ADDR"
}

send_tx() {
  local TO="$1"; local SIG="$2"; shift 2
  cast send "$TO" "$SIG" "$@" \
    --rpc-url "$RPC" \
    --private-key "$PRIVATE_KEY" \
    >/dev/null
  # Same nonce-settle wait as deploy_create — Base Sepolia public RPC lags.
  local DEPLOYER_ADDR
  DEPLOYER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)
  local TARGET_NONCE
  TARGET_NONCE=$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC" 2>/dev/null || echo 0)
  local WAITED=0
  while [ "$WAITED" -lt 30 ]; do
    local CUR
    CUR=$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC" 2>/dev/null || echo 0)
    if [ "$CUR" -ge "$TARGET_NONCE" ] 2>/dev/null; then
      break
    fi
    sleep 1
    WAITED=$((WAITED + 1))
  done
  sleep 2
}

# ── 1. SKRToken ─────────────────────────────────────────────────────────
echo
echo "═══ [1/10] SKRToken ═══"
TOKEN=$(deploy_create "src/SKRToken.sol:SKRToken" "$DEPLOYER")
echo "  SKRToken            $TOKEN"

# ── 2. StakingVault ────────────────────────────────────────────────────
echo
echo "═══ [2/10] StakingVault ═══"
VAULT=$(deploy_create "src/StakingVault.sol:StakingVault" "$TOKEN" "$DEPLOYER")
echo "  StakingVault        $VAULT"

# ── 3. AttestationStore ────────────────────────────────────────────────
echo
echo "═══ [3/10] AttestationStore ═══"
STORE=$(deploy_create "src/AttestationStore.sol:AttestationStore" "$DEPLOYER")
echo "  AttestationStore    $STORE"

# ── 4. ChallengeRegistry ───────────────────────────────────────────────
echo
echo "═══ [4/10] ChallengeRegistry ═══"
REGISTRY=$(deploy_create "src/ChallengeRegistry.sol:ChallengeRegistry" "$TOKEN" "$VAULT")
echo "  ChallengeRegistry   $REGISTRY"

# ── 5. MathGroth16Verifier ─────────────────────────────────────────────
echo
echo "═══ [5/10] MathGroth16Verifier ═══"
MATH_GROTH16=$(deploy_create "src/verifiers/MathVerifier.sol:MathGroth16Verifier")
echo "  MathGroth16Verifier $MATH_GROTH16"

# ── 6. MathVerifierAdapter ─────────────────────────────────────────────
echo
echo "═══ [6/10] MathVerifierAdapter ═══"
MATH_ADAPTER=$(deploy_create "src/verifiers/MathVerifierAdapter.sol:MathVerifierAdapter" "$MATH_GROTH16")
echo "  MathVerifierAdapter $MATH_ADAPTER"

# ── 7. FraudGroth16Verifier ────────────────────────────────────────────
echo
echo "═══ [7/10] FraudGroth16Verifier ═══"
FRAUD_GROTH16=$(deploy_create "src/verifiers/FraudVerifier.sol:FraudGroth16Verifier")
echo "  FraudGroth16Verifier $FRAUD_GROTH16"

# ── 8. FraudVerifierAdapter ────────────────────────────────────────────
echo
echo "═══ [8/10] FraudVerifierAdapter ═══"
FRAUD_ADAPTER=$(deploy_create "src/verifiers/FraudVerifierAdapter.sol:FraudVerifierAdapter" "$FRAUD_GROTH16")
echo "  FraudVerifierAdapter $FRAUD_ADAPTER"

# ── 9. AttestationEngine ───────────────────────────────────────────────
echo
echo "═══ [9/10] AttestationEngine ═══"
ENGINE=$(deploy_create "src/AttestationEngine.sol:AttestationEngine" \
  "$REGISTRY" "$VAULT" "$STORE" "$TOKEN" "$FRAUD_ADAPTER")
echo "  AttestationEngine   $ENGINE"

# ── 10. QueryGateway ───────────────────────────────────────────────────
echo
echo "═══ [10/10] QueryGateway ═══"
GATEWAY=$(deploy_create "src/QueryGateway.sol:QueryGateway" "$STORE")
echo "  QueryGateway        $GATEWAY"

# ── Wiring: setEngine on vault + store ─────────────────────────────────
echo
echo "═══ Post-deploy wiring ═══"
echo "[..] StakingVault.setEngine($ENGINE)"
send_tx "$VAULT" "setEngine(address)" "$ENGINE"
echo "[ok] vault.engine = $ENGINE"

echo "[..] AttestationStore.setEngine($ENGINE)"
send_tx "$STORE" "setEngine(address)" "$ENGINE"
echo "[ok] store.engine = $ENGINE"

# ── Genesis challenge: propose + one-shot activate ─────────────────────
echo
echo "═══ Genesis challenge (math / APPLIED_MATH) ═══"
PROPOSER_BOND="10000000000000000000000"   # 10_000 ether
SIGNAL_WEIGHT="100000000000000000000"     # 100 ether
APPLIED_MATH=2                            # enum index
ZERO_BYTES32="0x0000000000000000000000000000000000000000000000000000000000000000"

echo "[..] token.approve(registry, 10_000 SKR)"
send_tx "$TOKEN" "approve(address,uint256)" "$REGISTRY" "$PROPOSER_BOND"

echo "[..] registry.propose(APPLIED_MATH, mathAdapter, 0x00, 0x00, 100e18)"
send_tx "$REGISTRY" "propose(uint8,address,bytes32,bytes32,uint256)" \
  "$APPLIED_MATH" "$MATH_ADAPTER" "$ZERO_BYTES32" "$ZERO_BYTES32" "$SIGNAL_WEIGHT"

echo "[..] registry.genesisActivate(1)"
send_tx "$REGISTRY" "genesisActivate(uint256)" 1

GENESIS_BURNT=$(cast call "$REGISTRY" "genesisDeployer()(address)" --rpc-url "$RPC")
if [ "$(echo "$GENESIS_BURNT" | tr '[:upper:]' '[:lower:]')" = "0x0000000000000000000000000000000000000000" ]; then
  echo "[ok] genesis key burned (genesisDeployer = 0x0)"
else
  echo "[warn] genesisDeployer still $GENESIS_BURNT — expected 0x0"
fi

ACTIVE=$(cast call "$REGISTRY" "isActive(uint256)(bool)" 1 --rpc-url "$RPC")
if [ "$ACTIVE" = "true" ]; then
  echo "[ok] challenge 1 is ACTIVE"
else
  echo "[err] challenge 1 is not active — deploy incomplete"
  exit 1
fi

# ── Write deployment artifacts ─────────────────────────────────────────
echo
echo "═══ Writing artifacts ═══"

cat > "$OUT_FILE" <<JSON
{
  "chain": "base-sepolia",
  "chainId": 84532,
  "version": "$VERSION",
  "deployedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$DEPLOYER",
  "contracts": {
    "SKRToken":             "$TOKEN",
    "StakingVault":         "$VAULT",
    "AttestationStore":     "$STORE",
    "ChallengeRegistry":    "$REGISTRY",
    "AttestationEngine":    "$ENGINE",
    "QueryGateway":         "$GATEWAY",
    "MathGroth16Verifier":  "$MATH_GROTH16",
    "MathVerifierAdapter":  "$MATH_ADAPTER",
    "FraudGroth16Verifier": "$FRAUD_GROTH16",
    "FraudVerifierAdapter": "$FRAUD_ADAPTER"
  },
  "activeChallengeId": 1,
  "notes": "v0.2.0-no-vote: fraud proofs + auto-finalize. Genesis key burned. Run testnet-verify-novote.sh."
}
JSON
echo "[ok] $OUT_FILE"

APP_ENV="$ROOT/app/.env.local"
cat > "$APP_ENV" <<EOF
# Auto-generated by deploy-sepolia-novote.sh — $(date -u +%Y-%m-%dT%H:%M:%SZ)
NEXT_PUBLIC_CHAIN_ID=84532
NEXT_PUBLIC_SKR_TOKEN=$TOKEN
NEXT_PUBLIC_STAKING_VAULT=$VAULT
NEXT_PUBLIC_ATTESTATION_STORE=$STORE
NEXT_PUBLIC_CHALLENGE_REGISTRY=$REGISTRY
NEXT_PUBLIC_ATTESTATION_ENGINE=$ENGINE
NEXT_PUBLIC_QUERY_GATEWAY=$GATEWAY
NEXT_PUBLIC_MATH_VERIFIER=$MATH_ADAPTER
NEXT_PUBLIC_FRAUD_VERIFIER=$FRAUD_ADAPTER
NEXT_PUBLIC_ACTIVE_CHALLENGE_ID=1
NEXT_PUBLIC_WC_PROJECT_ID=${WC_PROJECT_ID:-}
EOF
echo "[ok] $APP_ENV"

# ── Optional Basescan verification ─────────────────────────────────────
if [ -n "${BASESCAN_API_KEY:-}" ]; then
  echo
  echo "[..] verifying on Basescan (non-blocking)"
  for pair in \
    "src/SKRToken.sol:SKRToken $TOKEN" \
    "src/StakingVault.sol:StakingVault $VAULT" \
    "src/AttestationStore.sol:AttestationStore $STORE" \
    "src/ChallengeRegistry.sol:ChallengeRegistry $REGISTRY" \
    "src/AttestationEngine.sol:AttestationEngine $ENGINE" \
    "src/QueryGateway.sol:QueryGateway $GATEWAY" \
    "src/verifiers/MathVerifier.sol:MathGroth16Verifier $MATH_GROTH16" \
    "src/verifiers/MathVerifierAdapter.sol:MathVerifierAdapter $MATH_ADAPTER" \
    "src/verifiers/FraudVerifier.sol:FraudGroth16Verifier $FRAUD_GROTH16" \
    "src/verifiers/FraudVerifierAdapter.sol:FraudVerifierAdapter $FRAUD_ADAPTER"; do
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
echo "  SkillRoot $VERSION deployed to Base Sepolia"
echo "  next → ./scripts/testnet-verify-novote.sh"
echo "════════════════════════════════════════════════════"
