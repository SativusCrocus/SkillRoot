#!/usr/bin/env bash
#
# anvil-e2e.sh — Gate 5: headless end-to-end validation on local anvil.
#
# Exercises the full v0 lifecycle in a single script:
#   1.  start anvil (kills on exit)
#   2.  deploy contracts with SKIP_GOV_TRANSFER=1 (deployer stays governance)
#   3.  deploy MathGroth16Verifier + MathVerifierAdapter
#   4.  fund + bond 7 validators (anvil accounts 1..7)
#   5.  propose + activate the math challenge
#   6.  generate a real Groth16 proof for (claimant, challengeId=1)
#   7.  submitClaim on AttestationEngine
#   8.  mine 5 blocks, drawCommittee
#   9.  parse committee, each member votes YES (via anvil_impersonateAccount)
#   10. advance 24h + 1s, finalize
#   11. query score via QueryGateway, assert > 0
#
# Requirements: anvil, cast, forge, node ≥20, snarkjs installed (see setup.sh).
#               circuits must already be built (scripts/build-circuits.sh).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CONTRACTS="$ROOT/contracts"
CIRCUITS="$ROOT/circuits"

# Ensure node + foundry are in PATH
if [ -d "$HOME/.nvm/versions/node" ]; then
  LATEST_NODE="$(ls -1 "$HOME/.nvm/versions/node" | sort -V | tail -n1)"
  export PATH="$HOME/.nvm/versions/node/$LATEST_NODE/bin:$PATH"
fi
export PATH="$HOME/.foundry/bin:$PATH"

# --- colours ----------------------------------------------------------------
RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[0;33m"; BLU="\033[0;34m"; NC="\033[0m"
ok()   { printf "${GRN}[ok]${NC} %s\n"   "$*"; }
info() { printf "${BLU}[..]${NC} %s\n"   "$*"; }
warn() { printf "${YEL}[warn]${NC} %s\n" "$*"; }
err()  { printf "${RED}[err]${NC} %s\n"  "$*" >&2; }

# --- anvil default accounts (deterministic test mnemonic) -------------------
# account 0 is the deployer and also the claimant in this script
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

VALIDATORS=(
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8
  0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
  0x90F79bf6EB2c4f870365E785982E1f101E93b906
  0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
  0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc
  0x976EA74026E726554dB657fA54763abd0C3a0aa9
  0x14dC79964da2C08b23698B3D3cc7Ca32193d9955
)

RPC="http://127.0.0.1:8545"
CHAIN_ID=31337
ANVIL_LOG="/tmp/anvil-e2e.log"
DEPLOY_LOG="/tmp/anvil-e2e-deploy.log"

# --- preconditions -----------------------------------------------------------
[ -f "$CIRCUITS/math/build/math_js/math.wasm" ] || {
  err "circuits not built — run ./scripts/build-circuits.sh first"
  exit 1
}
[ -f "$CIRCUITS/math/build/math_final.zkey" ] || {
  err "math_final.zkey not found — run ./scripts/build-circuits.sh first"
  exit 1
}
[ -f "$CONTRACTS/src/verifiers/MathVerifier.sol" ] || {
  err "MathVerifier.sol not installed — run ./scripts/build-circuits.sh first"
  exit 1
}

# --- cleanup -----------------------------------------------------------------
ANVIL_PID=""
cleanup() {
  if [ -n "$ANVIL_PID" ]; then
    kill "$ANVIL_PID" 2>/dev/null || true
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# --- 1. start anvil ----------------------------------------------------------
info "starting anvil (background, logs → $ANVIL_LOG)"
anvil --silent > "$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!

# wait for RPC to come up
for _ in $(seq 1 30); do
  if cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
CHAIN_ID_ONLINE=$(cast chain-id --rpc-url "$RPC" 2>/dev/null || echo "")
[ "$CHAIN_ID_ONLINE" = "$CHAIN_ID" ] || { err "anvil not responding on $RPC"; exit 1; }
ok "anvil up at $RPC (chainId=$CHAIN_ID_ONLINE, pid=$ANVIL_PID)"

# --- 2. deploy contracts (SKIP_GOV_TRANSFER=1) ------------------------------
info "deploying SkillRoot v0 contracts"
cd "$CONTRACTS"
SKIP_GOV_TRANSFER=1 PRIVATE_KEY="$DEPLOYER_PK" forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC" \
  --broadcast \
  -vv > "$DEPLOY_LOG" 2>&1 || {
    err "Deploy.s.sol failed — see $DEPLOY_LOG"
    tail -30 "$DEPLOY_LOG" >&2
    exit 1
  }

extract() {
  grep -oE "$1 +0x[a-fA-F0-9]{40}" "$DEPLOY_LOG" | awk '{print $NF}' | tail -n1
}
TOKEN=$(extract "SKRToken")
GOV=$(extract "Governance")
VAULT=$(extract "StakingVault")
REGISTRY=$(extract "ChallengeRegistry")
SORT=$(extract "Sortition")
STORE=$(extract "AttestationStore")
ENGINE=$(extract "AttestationEngine")
GATEWAY=$(extract "QueryGateway")

for addr in "$TOKEN" "$GOV" "$VAULT" "$REGISTRY" "$SORT" "$STORE" "$ENGINE" "$GATEWAY"; do
  [ -n "$addr" ] || { err "deploy parse failed — see $DEPLOY_LOG"; exit 1; }
done
ok "SKRToken          $TOKEN"
ok "Governance        $GOV"
ok "StakingVault      $VAULT"
ok "ChallengeRegistry $REGISTRY"
ok "Sortition         $SORT"
ok "AttestationStore  $STORE"
ok "AttestationEngine $ENGINE"
ok "QueryGateway      $GATEWAY"

# --- 3. deploy MathGroth16Verifier + MathVerifierAdapter --------------------
# forge create's --json flag is flaky when compilation is cached; parse text.
parse_deployed() {
  grep -oE "(Deployed to:|deployedTo[\":]+)\s*0x[a-fA-F0-9]{40}" | head -n1 | awk '{print $NF}' | tr -d '",'
}

info "deploying MathGroth16Verifier"
GROTH=$(forge create src/verifiers/MathVerifier.sol:MathGroth16Verifier \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" --broadcast 2>&1 | parse_deployed)
[ -n "$GROTH" ] || { err "failed to parse MathGroth16Verifier address"; exit 1; }
ok "MathGroth16Verifier $GROTH"

info "deploying MathVerifierAdapter"
VERIFIER=$(forge create src/verifiers/MathVerifierAdapter.sol:MathVerifierAdapter \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" --broadcast \
  --constructor-args "$GROTH" 2>&1 | parse_deployed)
[ -n "$VERIFIER" ] || { err "failed to parse MathVerifierAdapter address"; exit 1; }
ok "MathVerifierAdapter $VERIFIER"

# --- 4. fund + bond 7 validators --------------------------------------------
info "funding 7 validators with 2,000 SKR each"
for v in "${VALIDATORS[@]}"; do
  cast send "$TOKEN" "transfer(address,uint256)" "$v" "2000000000000000000000" \
    --rpc-url "$RPC" --private-key "$DEPLOYER_PK" >/dev/null
done
ok "funded"

info "bonding 7 validators (1,000 SKR each via impersonation)"
for v in "${VALIDATORS[@]}"; do
  cast rpc anvil_impersonateAccount "$v" --rpc-url "$RPC" >/dev/null
  # 1 ETH gas buffer (just in case)
  cast rpc anvil_setBalance "$v" "0x3635c9adc5dea00000" --rpc-url "$RPC" >/dev/null
  cast send "$TOKEN" "approve(address,uint256)" "$VAULT" "1000000000000000000000" \
    --rpc-url "$RPC" --from "$v" --unlocked >/dev/null
  cast send "$VAULT" "bond(uint256)" "1000000000000000000000" \
    --rpc-url "$RPC" --from "$v" --unlocked >/dev/null
  cast rpc anvil_stopImpersonatingAccount "$v" --rpc-url "$RPC" >/dev/null
done

VCOUNT=$(cast call "$VAULT" "validatorCount()(uint256)" --rpc-url "$RPC")
ok "validatorCount = $VCOUNT"
[ "$VCOUNT" = "7" ] || { err "expected 7 validators, got $VCOUNT"; exit 1; }

# --- 5. propose + activate the math challenge ------------------------------
info "proposing math challenge (domain=APPLIED_MATH=2)"
cast send "$TOKEN" "approve(address,uint256)" "$REGISTRY" \
  "115792089237316195423570985008687907853269984665640564039457584007913129639935" \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" >/dev/null

SPEC_CID="0x$(python3 -c "print('6d6174682d737065632d76303100'*3)" | cut -c1-64)"
CIRCUIT_HASH="0x$(python3 -c "print('6d6174685f6369726375697400'*3)" | cut -c1-64)"
SIGNAL_WEIGHT="1000000000000000000000"  # 1000 ether

cast send "$REGISTRY" "propose(uint8,address,bytes32,bytes32,uint256)" \
  2 "$VERIFIER" "$SPEC_CID" "$CIRCUIT_HASH" "$SIGNAL_WEIGHT" \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" >/dev/null

CHALLENGE_ID=$(($(cast call "$REGISTRY" "nextChallengeId()(uint256)" --rpc-url "$RPC" | awk '{print $1}') - 1))
ok "proposed challenge id=$CHALLENGE_ID"

info "activating challenge"
cast send "$REGISTRY" "activate(uint256)" "$CHALLENGE_ID" \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" >/dev/null
ACTIVE=$(cast call "$REGISTRY" "isActive(uint256)(bool)" "$CHALLENGE_ID" --rpc-url "$RPC")
[ "$ACTIVE" = "true" ] || { err "challenge not active"; exit 1; }
ok "challenge $CHALLENGE_ID active=$ACTIVE"

# --- 6. generate real Groth16 proof -----------------------------------------
info "computing bindingHash for (claimant=$DEPLOYER, challengeId=$CHALLENGE_ID)"
BINDING_DEC=$(cast call "$ENGINE" "bindingHashOf(address,uint256)(uint256)" \
  "$DEPLOYER" "$CHALLENGE_ID" --rpc-url "$RPC" | awk '{print $1}')
ok "bindingHash = $BINDING_DEC"

# Proof for: 2^20 mod 97 = 6
BASE=2
EXP=20
MOD=97
EXPECTED=6

PROOF_DIR="/tmp/anvil-e2e-proof"
rm -rf "$PROOF_DIR"
mkdir -p "$PROOF_DIR"
INPUT_FILE="$PROOF_DIR/input.json"

info "generating witness input (base=$BASE, exp=$EXP, mod=$MOD → $EXPECTED)"
cd "$CIRCUITS/scripts"
# Ensure the scripts package has its deps
if [ ! -d node_modules ]; then
  info "installing circuit scripts deps"
  if command -v pnpm >/dev/null 2>&1; then
    pnpm install
  else
    npm install
  fi
fi

TSX_BIN="$CIRCUITS/scripts/node_modules/.bin/tsx"
[ -x "$TSX_BIN" ] || { err "tsx binary not found at $TSX_BIN"; exit 1; }

"$TSX_BIN" gen-input.ts "$BINDING_DEC" "$BASE" "$EXP" "$MOD" "$INPUT_FILE"
ok "wrote $INPUT_FILE"

info "generating Groth16 proof (this may take a few seconds)"
"$TSX_BIN" prove.ts "$INPUT_FILE" \
  "$CIRCUITS/math/build/math_js/math.wasm" \
  "$CIRCUITS/math/build/math_final.zkey" \
  "$PROOF_DIR" 2>&1 | tail -5
ok "proof generated"

# Parse calldata.json
CALL="$PROOF_DIR/calldata.json"
A0=$(python3 -c "import json; d=json.load(open('$CALL')); print(d['a'][0])")
A1=$(python3 -c "import json; d=json.load(open('$CALL')); print(d['a'][1])")
B00=$(python3 -c "import json; d=json.load(open('$CALL')); print(d['b'][0][0])")
B01=$(python3 -c "import json; d=json.load(open('$CALL')); print(d['b'][0][1])")
B10=$(python3 -c "import json; d=json.load(open('$CALL')); print(d['b'][1][0])")
B11=$(python3 -c "import json; d=json.load(open('$CALL')); print(d['b'][1][1])")
C0=$(python3 -c "import json; d=json.load(open('$CALL')); print(d['c'][0])")
C1=$(python3 -c "import json; d=json.load(open('$CALL')); print(d['c'][1])")

# circuitSignals = [base, modulus, result] (drop signal[0] = bindingHash)
A_ARG="[$A0,$A1]"
B_ARG="[[$B00,$B01],[$B10,$B11]]"
C_ARG="[$C0,$C1]"
SIGNALS_ARG="[$BASE,$MOD,$EXPECTED]"

# --- 7. submitClaim ----------------------------------------------------------
info "submitting claim"
ARTIFACT_CID="0x$(python3 -c "print('617274696661637400'*8)" | cut -c1-64)"
cd "$CONTRACTS"
SUBMIT_TX=$(cast send "$ENGINE" \
  "submitClaim(uint256,uint256[2],uint256[2][2],uint256[2],uint256[],bytes32)" \
  "$CHALLENGE_ID" "$A_ARG" "$B_ARG" "$C_ARG" "$SIGNALS_ARG" "$ARTIFACT_CID" \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])")
ok "submitClaim tx=$SUBMIT_TX"

CLAIM_ID=$(($(cast call "$ENGINE" "nextClaimId()(uint256)" --rpc-url "$RPC" | awk '{print $1}') - 1))
ok "claim id=$CLAIM_ID"

SUBMIT_BLOCK=$(cast tx "$SUBMIT_TX" --rpc-url "$RPC" --json | python3 -c "import json,sys; print(int(json.load(sys.stdin)['blockNumber'], 16))")
ok "submitted at block $SUBMIT_BLOCK"

# --- 8. mine 5 blocks, drawCommittee ----------------------------------------
info "mining 5 blocks (REVEAL_DELAY=4)"
cast rpc anvil_mine 0x5 --rpc-url "$RPC" >/dev/null
ok "advanced to block $(cast block-number --rpc-url "$RPC")"

info "drawCommittee"
cast send "$ENGINE" "drawCommittee(uint256)" "$CLAIM_ID" \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" >/dev/null

COMMITTEE_RAW=$(cast call "$ENGINE" "committeeOf(uint256)(address[])" "$CLAIM_ID" --rpc-url "$RPC")
# Parse the output "[0x..., 0x..., ...]"
COMMITTEE=$(echo "$COMMITTEE_RAW" | tr -d '[]' | tr ',' '\n' | tr -d ' ')
COMMITTEE_SIZE=$(echo "$COMMITTEE" | grep -c '^0x' || true)
ok "committee size = $COMMITTEE_SIZE"
echo "$COMMITTEE" | sed 's/^/     /'
[ "$COMMITTEE_SIZE" -ge 1 ] || { err "no committee members drawn"; exit 1; }

# --- 9. each committee member votes YES ------------------------------------
info "committee votes YES"
for v in $COMMITTEE; do
  [ -z "$v" ] && continue
  cast rpc anvil_impersonateAccount "$v" --rpc-url "$RPC" >/dev/null
  cast rpc anvil_setBalance "$v" "0x3635c9adc5dea00000" --rpc-url "$RPC" >/dev/null
  cast send "$ENGINE" "vote(uint256,bool)" "$CLAIM_ID" "true" \
    --rpc-url "$RPC" --from "$v" --unlocked >/dev/null
  cast rpc anvil_stopImpersonatingAccount "$v" --rpc-url "$RPC" >/dev/null
  printf "     ${GRN}✓${NC} %s voted YES\n" "$v"
done

# --- 10. advance 24h + 1s, finalize -----------------------------------------
info "advancing time past VOTE_WINDOW (24h + 1)"
cast rpc evm_increaseTime 86401 --rpc-url "$RPC" >/dev/null
cast rpc anvil_mine 0x1 --rpc-url "$RPC" >/dev/null

info "finalize"
cast send "$ENGINE" "finalize(uint256)" "$CLAIM_ID" \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" >/dev/null

CLAIM_STATUS=$(cast call "$ENGINE" "getClaim(uint256)((uint256,uint256,address,uint64,uint64,bytes32,uint8,uint8,uint8))" "$CLAIM_ID" --rpc-url "$RPC")
# status enum: 0=SUBMITTED, 1=COMMITTEE_DRAWN, 2=FINALIZED_ACCEPT, 3=FINALIZED_REJECT, 4=EXPIRED
ok "claim status (tuple) = $CLAIM_STATUS"

# --- 11. query score via QueryGateway ---------------------------------------
info "query QueryGateway.verify($DEPLOYER)"
SCORES=$(cast call "$GATEWAY" "verify(address)(uint256[4])" "$DEPLOYER" --rpc-url "$RPC")
ok "scores = $SCORES"

# APPLIED_MATH ordinal = 2 → index 2 in [algo, formalVer, appliedMath, secCode]
# cast renders arrays as "[a, b, c, d]" where each value may carry a
# scientific-notation annotation like "1000000000000000000000 [1e21]".
# Strip the annotations first, then split on commas.
APPLIED_MATH_SCORE=$(echo "$SCORES" \
  | sed -E 's/\[[^][]*\]//g' \
  | tr -d '[]' \
  | awk -F',' '{gsub(/ /, "", $3); print $3}')
ok "applied-math score = $APPLIED_MATH_SCORE"

if [ -z "$APPLIED_MATH_SCORE" ] || [ "$APPLIED_MATH_SCORE" = "0" ]; then
  err "applied-math score is zero — expected >0 after acceptance"
  exit 1
fi

# --- 12. frontend static export build ----------------------------------------
info "building frontend static export"
cd "$ROOT"
pnpm build:app 2>&1 | tail -5
if [ -d "$ROOT/app/out" ]; then
  ok "frontend static export verified (app/out/)"
else
  err "frontend build did not produce app/out/"
  exit 1
fi

echo
printf "${GRN}=============================================${NC}\n"
printf "${GRN}  Gate 5 PASS — full lifecycle green         ${NC}\n"
printf "${GRN}  + frontend 3D static export verified       ${NC}\n"
printf "${GRN}=============================================${NC}\n"
echo "  deployer / claimant : $DEPLOYER"
echo "  challenge id        : $CHALLENGE_ID"
echo "  claim id            : $CLAIM_ID"
echo "  committee size      : $COMMITTEE_SIZE"
echo "  applied-math score  : $APPLIED_MATH_SCORE"
echo "  frontend            : app/out/ (static export)"
