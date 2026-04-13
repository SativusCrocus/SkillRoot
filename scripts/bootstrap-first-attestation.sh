#!/usr/bin/env bash
#
# bootstrap-first-attestation.sh — First live SkillRoot v0 attestation on Base Sepolia
#
#   1. Generate 5 validator keypairs (idempotent — reuses if exists)
#   2. Fund each with ETH (gas) + 5,000 SKR from deployer treasury
#   3. Stake 5,000 SKR per validator via `skr stake`
#   4. Start 5 parallel `skr validate` daemons
#   5. Generate ZK proof for math challenge (3^7 mod 13 = 3)
#   6. Submit founder attestation via `skr submit`
#   7. Wait for Sortition reveal window, draw committee
#   8. Wait for validator votes (~30s)
#   9. Wait for 24h vote window, finalize, confirm on-chain
#
# Prerequisites:
#   .env                           PRIVATE_KEY + BASE_SEPOLIA_RPC_URL
#   deployments/base-sepolia.json  from deploy-sepolia.sh
#   circuits built                 from build-circuits.sh
#   challenge #1 active            from seed-challenges.sh
#
# Usage:
#   ./scripts/bootstrap-first-attestation.sh              # full run, waits for finalize
#   ./scripts/bootstrap-first-attestation.sh --no-wait     # stop after votes, print finalize cmd
#   ./scripts/bootstrap-first-attestation.sh --finalize-only <claimId>

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# --- Colours ----------------------------------------------------------------
RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[0;33m"; BLU="\033[0;34m"
CYN="\033[0;36m"; NC="\033[0m"
ok()   { printf "${GRN}[ok]${NC} %s\n"   "$*"; }
info() { printf "${BLU}[..]${NC} %s\n"   "$*"; }
warn() { printf "${YEL}[!!]${NC} %s\n"   "$*"; }
err()  { printf "${RED}[err]${NC} %s\n"  "$*" >&2; }
hdr()  { printf "\n${CYN}=== %s ===${NC}\n\n" "$*"; }

# --- Flags ------------------------------------------------------------------
NO_WAIT=0
FINALIZE_ONLY=0
FINALIZE_CLAIM_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-wait)       NO_WAIT=1; shift ;;
    --finalize-only) FINALIZE_ONLY=1; FINALIZE_CLAIM_ID="${2:?usage: --finalize-only <claimId>}"; shift 2 ;;
    *)               err "unknown flag: $1"; exit 1 ;;
  esac
done

# --- Environment ------------------------------------------------------------
export PATH="$HOME/.foundry/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  LATEST_NODE="$(ls -1 "$HOME/.nvm/versions/node" | sort -V | tail -n1)"
  export PATH="$HOME/.nvm/versions/node/$LATEST_NODE/bin:$PATH"
fi

[ -f "$ROOT/.env" ] || { err ".env not found — need PRIVATE_KEY + BASE_SEPOLIA_RPC_URL"; exit 1; }
set -a; source "$ROOT/.env"; set +a

: "${PRIVATE_KEY:?set PRIVATE_KEY in .env}"
: "${BASE_SEPOLIA_RPC_URL:?set BASE_SEPOLIA_RPC_URL in .env}"

DEPLOYER_PK="$PRIVATE_KEY"
RPC="$BASE_SEPOLIA_RPC_URL"
DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PK")
DEPLOY_JSON="$ROOT/deployments/base-sepolia.json"

[ -f "$DEPLOY_JSON" ] || { err "no deployment at $DEPLOY_JSON — run deploy-sepolia.sh first"; exit 1; }

# --- Parse deployment addresses ---------------------------------------------
p() { python3 -c "import json; print(json.load(open('$DEPLOY_JSON'))['contracts']['$1'])"; }
TOKEN=$(p SKRToken)
VAULT=$(p StakingVault)
REGISTRY=$(p ChallengeRegistry)
ENGINE=$(p AttestationEngine)
GATEWAY=$(p QueryGateway)
GOVERNANCE=$(p Governance)

# --- Write CLI config (maps deployment keys → CLI keys) ---------------------
CLI_CONFIG="$HOME/.skr/deployments/base-sepolia.json"
mkdir -p "$(dirname "$CLI_CONFIG")"
cat > "$CLI_CONFIG" <<JSON
{
  "chainId": 84532,
  "rpcUrl": "$RPC",
  "contracts": {
    "token":      "$TOKEN",
    "vault":      "$VAULT",
    "registry":   "$REGISTRY",
    "engine":     "$ENGINE",
    "gateway":    "$GATEWAY",
    "governance": "$GOVERNANCE"
  }
}
JSON

# --- Preconditions ----------------------------------------------------------
[ -f "$ROOT/circuits/math/build/math_js/math.wasm" ] || {
  err "circuits not built — run ./scripts/build-circuits.sh first"; exit 1; }
[ -f "$ROOT/circuits/math/build/math_final.zkey" ] || {
  err "math_final.zkey missing — run ./scripts/build-circuits.sh first"; exit 1; }

CHALLENGE_ACTIVE=$(cast call "$REGISTRY" "isActive(uint256)(bool)" 1 --rpc-url "$RPC" 2>/dev/null || echo "false")
[ "$CHALLENGE_ACTIVE" = "true" ] || {
  err "challenge #1 not active — run seed-challenges.sh first"; exit 1; }

# --- Build CLI --------------------------------------------------------------
info "building CLI"
pnpm -C "$ROOT/cli" build --silent 2>&1 | tail -2
SKR="node $ROOT/cli/dist/bin.js"
ok "CLI ready"

# --- Constants --------------------------------------------------------------
NUM_VAL=5
STAKE_SKR=5000
ETH_PER_VAL="0.005"
VAL_DIR="$HOME/.skr/validators"
LOG_DIR="$HOME/.skr/logs"
mkdir -p "$VAL_DIR" "$LOG_DIR"

STAKE_WEI=$(python3 -c "print($STAKE_SKR * 10**18)")

echo
echo "  deployer     : $DEPLOYER"
echo "  rpc          : $RPC"
echo "  engine       : $ENGINE"
echo "  vault        : $VAULT"
echo "  gateway      : $GATEWAY"
echo "  validators   : $NUM_VAL x $STAKE_SKR SKR"

# --- Helper: parse getClaim tuple -------------------------------------------
# getClaim returns (id, challengeId, claimant, submissionBlock, voteDeadline,
#                   artifactCID, status, yesVotes, noVotes)
read_claim() {
  local cid="$1"
  CLAIM_RAW=$(cast call "$ENGINE" \
    "getClaim(uint256)(uint256,uint256,address,uint64,uint64,bytes32,uint8,uint8,uint8)" \
    "$cid" --rpc-url "$RPC")
  CLAIM_CLAIMANT=$(echo "$CLAIM_RAW" | sed -n '3p' | awk '{print $1}')
  CLAIM_DEADLINE=$(echo "$CLAIM_RAW" | sed -n '5p' | awk '{print $1}')
  CLAIM_STATUS=$(echo "$CLAIM_RAW" | sed -n '7p' | awk '{print $1}')
  CLAIM_YES=$(echo "$CLAIM_RAW" | sed -n '8p' | awk '{print $1}')
  CLAIM_NO=$(echo "$CLAIM_RAW" | sed -n '9p' | awk '{print $1}')
}

# ============================================================================
#  FINALIZE-ONLY MODE
# ============================================================================
if [ "$FINALIZE_ONLY" = "1" ]; then
  hdr "Finalize claim #$FINALIZE_CLAIM_ID"
  read_claim "$FINALIZE_CLAIM_ID"

  echo "  status    : $CLAIM_STATUS (1=COMMITTEE_DRAWN, 2=ACCEPT, 3=REJECT)"
  echo "  votes     : $CLAIM_YES yes / $CLAIM_NO no"
  echo "  deadline  : $(date -r "$CLAIM_DEADLINE" 2>/dev/null || echo "$CLAIM_DEADLINE")"

  NOW=$(date +%s)
  if [ "$NOW" -le "$CLAIM_DEADLINE" ]; then
    REMAINING=$((CLAIM_DEADLINE - NOW))
    warn "vote window open — ${REMAINING}s remaining"
    info "polling until deadline..."
    while [ "$(date +%s)" -le "$CLAIM_DEADLINE" ]; do
      sleep 60
      printf "."
    done
    echo
  fi

  info "finalizing"
  cast send "$ENGINE" "finalize(uint256)" "$FINALIZE_CLAIM_ID" \
    --rpc-url "$RPC" --private-key "$DEPLOYER_PK"
  ok "finalized"

  info "querying score"
  PRIVATE_KEY="$DEPLOYER_PK" $SKR query "$CLAIM_CLAIMANT"

  SCORES=$(cast call "$GATEWAY" "verify(address)(uint256[4])" "$CLAIM_CLAIMANT" --rpc-url "$RPC")
  ok "raw scores: $SCORES"

  printf "\n${GRN}  FIRST ATTESTATION FINALIZED ON BASE SEPOLIA${NC}\n"
  echo "  basescan: https://sepolia.basescan.org/address/$ENGINE"
  exit 0
fi

# ============================================================================
#  PHASE 1 — Generate & fund 5 validator wallets
# ============================================================================
hdr "Phase 1 / 8 — Generate & fund $NUM_VAL validators"

VAL_PKS=()
VAL_ADDRS=()

for i in $(seq 0 $((NUM_VAL - 1))); do
  KEY_FILE="$VAL_DIR/validator-$i.key"
  if [ -f "$KEY_FILE" ]; then
    PK=$(cat "$KEY_FILE")
    info "validator $i — reusing existing key"
  else
    PK="0x$(openssl rand -hex 32)"
    printf "%s" "$PK" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
  fi
  ADDR=$(cast wallet address --private-key "$PK")
  VAL_PKS+=("$PK")
  VAL_ADDRS+=("$ADDR")
  echo "  v$i : $ADDR"
done

# Check if validators already staked (idempotent)
EXISTING_VCOUNT=$(cast call "$VAULT" "validatorCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
if [ "$EXISTING_VCOUNT" -ge "$NUM_VAL" ]; then
  ok "$EXISTING_VCOUNT validators already bonded — skipping fund+stake"
  SKIP_FUND_STAKE=1
else
  SKIP_FUND_STAKE=0
fi

if [ "$SKIP_FUND_STAKE" = "0" ]; then
  info "funding $ETH_PER_VAL ETH per validator (gas)"
  for i in $(seq 0 $((NUM_VAL - 1))); do
    cast send "${VAL_ADDRS[$i]}" \
      --value "${ETH_PER_VAL}ether" \
      --rpc-url "$RPC" \
      --private-key "$DEPLOYER_PK" \
      --json 2>/dev/null | python3 -c "
import json, sys
tx = json.load(sys.stdin)
print(f'  v$i eth  : {tx[\"transactionHash\"][:18]}...')" 2>/dev/null
  done
  ok "ETH funded"

  info "transferring $STAKE_SKR SKR per validator"
  for i in $(seq 0 $((NUM_VAL - 1))); do
    cast send "$TOKEN" "transfer(address,uint256)" \
      "${VAL_ADDRS[$i]}" "$STAKE_WEI" \
      --rpc-url "$RPC" \
      --private-key "$DEPLOYER_PK" \
      --json 2>/dev/null | python3 -c "
import json, sys
tx = json.load(sys.stdin)
print(f'  v$i skr  : {tx[\"transactionHash\"][:18]}...')" 2>/dev/null
  done
  ok "SKR funded"
fi

# ============================================================================
#  PHASE 2 — Stake via CLI
# ============================================================================
hdr "Phase 2 / 8 — Stake $STAKE_SKR SKR per validator"

if [ "$SKIP_FUND_STAKE" = "0" ]; then
  for i in $(seq 0 $((NUM_VAL - 1))); do
    info "staking v$i (${VAL_ADDRS[$i]})"
    PRIVATE_KEY="${VAL_PKS[$i]}" $SKR stake "$STAKE_SKR"
  done
fi

VCOUNT=$(cast call "$VAULT" "validatorCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
ok "validatorCount = $VCOUNT"
[ "$VCOUNT" -ge "$NUM_VAL" ] || { err "expected >= $NUM_VAL validators, got $VCOUNT"; exit 1; }

# ============================================================================
#  PHASE 3 — Start 5 parallel validator daemons
# ============================================================================
hdr "Phase 3 / 8 — Start $NUM_VAL validator daemons"

VAL_PIDS=()
for i in $(seq 0 $((NUM_VAL - 1))); do
  PRIVATE_KEY="${VAL_PKS[$i]}" $SKR validate --skip-verify \
    > "$LOG_DIR/validator-$i.log" 2>&1 &
  VAL_PIDS+=($!)
  ok "v$i daemon pid=${VAL_PIDS[$i]}  log=$LOG_DIR/validator-$i.log"
done

cleanup() {
  info "stopping validator daemons"
  for pid in "${VAL_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 3  # let daemons initialise and start polling

# ============================================================================
#  PHASE 4 — Generate ZK proof (founder attestation)
# ============================================================================
hdr "Phase 4 / 8 — Generate founder proof (3^7 mod 13)"

cd "$ROOT"
PRIVATE_KEY="$DEPLOYER_PK" $SKR solve 1 --base 3 --exp 7 --mod 13
ok "proof at proofs/calldata-1.json"

# ============================================================================
#  PHASE 5 — Submit attestation
# ============================================================================
hdr "Phase 5 / 8 — Submit attestation"

PRIVATE_KEY="$DEPLOYER_PK" $SKR submit proofs/calldata-1.json --challenge 1
CLAIM_ID=$(( $(cast call "$ENGINE" "nextClaimId()(uint256)" --rpc-url "$RPC" | awk '{print $1}') - 1 ))
ok "claim id = $CLAIM_ID"

# ============================================================================
#  PHASE 6 — Draw committee via Sortition
# ============================================================================
hdr "Phase 6 / 8 — Draw committee"

info "waiting for Sortition reveal window (REVEAL_DELAY=4 blocks, ~8s on Base Sepolia)"
sleep 12

info "drawCommittee($CLAIM_ID)"
cast send "$ENGINE" "drawCommittee(uint256)" "$CLAIM_ID" \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" >/dev/null
ok "committee drawn"

COMMITTEE=$(cast call "$ENGINE" "committeeOf(uint256)(address[])" "$CLAIM_ID" --rpc-url "$RPC")
echo "  committee: $COMMITTEE"

# ============================================================================
#  PHASE 7 — Wait for validator votes
# ============================================================================
hdr "Phase 7 / 8 — Wait for validator votes"

info "daemons poll every 4s — waiting up to 60s for votes"
for tick in $(seq 1 12); do
  sleep 5
  read_claim "$CLAIM_ID"
  printf "  [%02ds] %s yes / %s no\n" $((tick * 5)) "$CLAIM_YES" "$CLAIM_NO"
  # If we have enough yes votes to pass quorum (66.66% of 7 = 5 minimum)
  if [ "${CLAIM_YES:-0}" -ge 5 ] 2>/dev/null; then
    ok "quorum reached"
    break
  fi
done

read_claim "$CLAIM_ID"
DEADLINE_HUMAN=$(date -r "$CLAIM_DEADLINE" 2>/dev/null || echo "unix:$CLAIM_DEADLINE")

echo
ok "votes: $CLAIM_YES yes / $CLAIM_NO no"
ok "vote deadline: $DEADLINE_HUMAN"
echo "  claim id  : $CLAIM_ID"
echo "  engine    : $ENGINE"
echo "  basescan  : https://sepolia.basescan.org/address/$ENGINE"

# ============================================================================
#  PHASE 8 — Finalize + confirm
# ============================================================================
if [ "$NO_WAIT" = "1" ]; then
  hdr "Phase 8 / 8 — SKIPPED (--no-wait)"
  echo "  To finalize after vote deadline:"
  echo
  echo "    ./scripts/bootstrap-first-attestation.sh --finalize-only $CLAIM_ID"
  echo
  echo "  Or manually:"
  echo "    source .env"
  echo "    cast send $ENGINE 'finalize(uint256)' $CLAIM_ID \\"
  echo "      --rpc-url \$BASE_SEPOLIA_RPC_URL --private-key \$PRIVATE_KEY"
  echo "    PRIVATE_KEY=\$PRIVATE_KEY $SKR query $DEPLOYER"
  echo
else
  hdr "Phase 8 / 8 — Finalize"

  NOW=$(date +%s)
  if [ "$NOW" -le "$CLAIM_DEADLINE" ]; then
    REMAINING=$((CLAIM_DEADLINE - NOW))
    HOURS=$((REMAINING / 3600))
    MINS=$(( (REMAINING % 3600) / 60 ))
    info "vote window closes in ${HOURS}h ${MINS}m — polling every 5 minutes"
    info "Ctrl+C safe: re-run with --finalize-only $CLAIM_ID"
    while [ "$(date +%s)" -le "$CLAIM_DEADLINE" ]; do
      sleep 300
      REMAINING=$((CLAIM_DEADLINE - $(date +%s)))
      if [ "$REMAINING" -gt 0 ]; then
        printf "  %dh %dm remaining...\n" $((REMAINING / 3600)) $(( (REMAINING % 3600) / 60 ))
      fi
    done
  fi

  info "finalizing claim #$CLAIM_ID"
  cast send "$ENGINE" "finalize(uint256)" "$CLAIM_ID" \
    --rpc-url "$RPC" --private-key "$DEPLOYER_PK"
  ok "finalized"

  read_claim "$CLAIM_ID"
  case "$CLAIM_STATUS" in
    2) ok "status = FINALIZED_ACCEPT" ;;
    3) err "status = FINALIZED_REJECT"; exit 1 ;;
    *) err "unexpected status = $CLAIM_STATUS"; exit 1 ;;
  esac

  info "querying decayed scores for $DEPLOYER"
  PRIVATE_KEY="$DEPLOYER_PK" $SKR query "$DEPLOYER"

  SCORES=$(cast call "$GATEWAY" "verify(address)(uint256[4])" "$DEPLOYER" --rpc-url "$RPC")

  echo
  printf "${GRN}================================================================${NC}\n"
  printf "${GRN}  FIRST LIVE ATTESTATION — FINALIZED ON BASE SEPOLIA           ${NC}\n"
  printf "${GRN}================================================================${NC}\n"
  echo "  deployer / claimant : $DEPLOYER"
  echo "  claim id            : $CLAIM_ID"
  echo "  votes               : $CLAIM_YES yes / $CLAIM_NO no"
  echo "  validators bonded   : $VCOUNT"
  echo "  scores              : $SCORES"
  echo "  engine              : $ENGINE"
  echo "  basescan            : https://sepolia.basescan.org/address/$ENGINE"
  echo "  frontend            : https://app-nine-rho-70.vercel.app"
  echo
fi
