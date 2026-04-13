# First Attestation on Base Sepolia

End-to-end: fund wallets → bootstrap validators → solve modexp → submit proof → committee vote → finalize → verify live.

## Prerequisites

| Tool | Check |
|------|-------|
| Foundry | `forge --version` |
| Node 20+ | `node -v` |
| pnpm 9+ | `pnpm -v` |
| Deployed contracts | `cat deployments/base-sepolia.json` |
| Seeded challenge | challenge 1 = ACTIVE |
| Circuit artifacts | `circuits/math/build/math_js/math.wasm` + `math_final.zkey` |

If circuits aren't built yet:

```bash
./scripts/build-circuits.sh
```

---

## Step 0 — Load deployment context

```bash
source .env

PRIVATE_KEY="$DEPLOYER_PRIVATE_KEY"
RPC="$BASE_SEPOLIA_RPC"
DEPLOY="deployments/base-sepolia.json"

TOKEN=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['contracts']['SKRToken'])")
VAULT=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['contracts']['StakingVault'])")
REGISTRY=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['contracts']['ChallengeRegistry'])")
ENGINE=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['contracts']['AttestationEngine'])")
GATEWAY=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['contracts']['QueryGateway'])")
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")

echo "deployer = $DEPLOYER"
echo "token    = $TOKEN"
echo "vault    = $VAULT"
echo "engine   = $ENGINE"
```

---

## Step 1 — Fund the deployer with Sepolia ETH

Base Sepolia faucet: <https://www.coinbase.com/faucets/base-ethereum-goerli-faucet>

Request 0.1 ETH to the deployer address. Confirm:

```bash
cast balance "$DEPLOYER" --rpc-url "$RPC"
```

---

## Step 2 — Bootstrap 7 validators

The sortition committee requires 7 distinct staked validators. Generate wallets, fund each with ETH + 5,000 SKR, and bond.

```bash
VALIDATORS_FILE="/tmp/skr-validators.json"
echo "[]" > "$VALIDATORS_FILE"

for i in $(seq 1 7); do
  RAW=$(cast wallet new 2>&1)
  ADDR=$(echo "$RAW" | grep "Address:" | awk '{print $2}')
  PK=$(echo "$RAW" | grep "Private key:" | awk '{print $3}')
  python3 -c "
import json
v = json.load(open('$VALIDATORS_FILE'))
v.append({'address': '$ADDR', 'key': '$PK'})
json.dump(v, open('$VALIDATORS_FILE', 'w'), indent=2)
"
  echo "  validator $i: $ADDR"
done

echo "[ok] saved to $VALIDATORS_FILE"
```

### 2a — Send ETH to each validator

```bash
python3 -c "
import json
for v in json.load(open('$VALIDATORS_FILE')):
    print(v['address'])
" | while read ADDR; do
  cast send "$ADDR" --value 0.005ether \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
  echo "  funded $ADDR with 0.005 ETH"
done
```

### 2b — Transfer 5,000 SKR to each validator

```bash
AMT="5000000000000000000000"  # 5000e18

python3 -c "
import json
for v in json.load(open('$VALIDATORS_FILE')):
    print(v['address'])
" | while read ADDR; do
  cast send "$TOKEN" "transfer(address,uint256)" "$ADDR" "$AMT" \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
  echo "  sent 5000 SKR → $ADDR"
done
```

### 2c — Approve + bond from each validator

```bash
python3 -c "
import json
for v in json.load(open('$VALIDATORS_FILE')):
    print(v['key'])
" | while read VK; do
  cast send "$TOKEN" "approve(address,uint256)" "$VAULT" "$(cast max-uint)" \
    --rpc-url "$RPC" --private-key "$VK" >/dev/null
  cast send "$VAULT" "bond(uint256)" "$AMT" \
    --rpc-url "$RPC" --private-key "$VK" >/dev/null
  VADDR=$(cast wallet address --private-key "$VK")
  STAKE=$(cast call "$VAULT" "stakeOf(address)(uint256)" "$VADDR" --rpc-url "$RPC")
  echo "  bonded $VADDR  stake=$STAKE"
done
```

Verify validator count:

```bash
cast call "$VAULT" "validatorCount()(uint256)" --rpc-url "$RPC"
# Expected: 7
```

---

## Step 3 — Solve the modexp challenge

Pick parameters. The proof demonstrates knowledge of `exponent` such that `base^exponent mod modulus == result`.

| Param | Value | Visibility |
|-------|-------|------------|
| base | 2 | public |
| exponent | 20 | **private** (only prover knows) |
| modulus | 97 | public |
| result | 55 | public (2^20 mod 97 = 55) |

### Using the CLI

```bash
export SKR_RPC_URL="$RPC"
export SKR_CHAIN_ID=84532

skr solve 1 \
  --base 2 --exp 20 --mod 97 \
  --wasm ./circuits/math/build/math_js/math.wasm \
  --zkey ./circuits/math/build/math_final.zkey \
  --out ./proofs
```

Output: `./proofs/calldata-1.json` — contains `a`, `b`, `c`, `circuitSignals` ready for on-chain submission.

### Alternative: circuit scripts directly

```bash
# Generate witness input
npx tsx circuits/scripts/gen-input.ts \
  "$(cast call "$ENGINE" "bindingHashOf(address,uint256)(uint256)" "$DEPLOYER" 1 --rpc-url "$RPC")" \
  2 20 97 ./proofs/input-1.json

# Generate Groth16 proof
npx tsx circuits/scripts/prove.ts \
  ./proofs/input-1.json \
  ./circuits/math/build/math_js/math.wasm \
  ./circuits/math/build/math_final.zkey \
  ./proofs
```

Output: `./proofs/calldata.json`

---

## Step 4 — Submit proof on-chain

### Using the CLI

```bash
skr submit ./proofs/calldata-1.json --challenge 1
```

Returns: `claimId` (should be `1` on a fresh deployment).

### Alternative: cast

```bash
CALLDATA=$(cat ./proofs/calldata-1.json)

# Extract proof components
A0=$(echo "$CALLDATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['a'][0])")
A1=$(echo "$CALLDATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['a'][1])")
B00=$(echo "$CALLDATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['b'][0][0])")
B01=$(echo "$CALLDATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['b'][0][1])")
B10=$(echo "$CALLDATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['b'][1][0])")
B11=$(echo "$CALLDATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['b'][1][1])")
C0=$(echo "$CALLDATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['c'][0])")
C1=$(echo "$CALLDATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['c'][1])")
SIGS=$(echo "$CALLDATA" | python3 -c "
import json,sys; d=json.load(sys.stdin)
print('[' + ','.join(d['circuitSignals']) + ']')
")

cast send "$ENGINE" \
  "submitClaim(uint256,(uint256,uint256),((uint256,uint256),(uint256,uint256)),(uint256,uint256),uint256[],bytes32)" \
  1 "($A0,$A1)" "(($B00,$B01),($B10,$B11))" "($C0,$C1)" "$SIGS" "0x0000000000000000000000000000000000000000000000000000000000000000" \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY"
```

Record the claim ID:

```bash
CLAIM_ID=$(cast call "$ENGINE" "nextClaimId()(uint256)" --rpc-url "$RPC")
CLAIM_ID=$((CLAIM_ID - 1))
echo "claimId = $CLAIM_ID"
```

---

## Step 5 — Draw committee

Wait at least 4 blocks (~8 seconds on Base Sepolia) for blockhash entropy, then:

```bash
sleep 10

cast send "$ENGINE" "drawCommittee(uint256)" "$CLAIM_ID" \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY"
```

Verify:

```bash
cast call "$ENGINE" "claimStatus(uint256)(uint8)" "$CLAIM_ID" --rpc-url "$RPC"
# Expected: 1 (COMMITTEE_DRAWN)
```

---

## Step 6 — Validators vote

Each committee member votes YES within the 24-hour window.

```bash
python3 -c "
import json
for v in json.load(open('$VALIDATORS_FILE')):
    print(v['key'])
" | while read VK; do
  cast send "$ENGINE" "vote(uint256,bool)" "$CLAIM_ID" true \
    --rpc-url "$RPC" --private-key "$VK" 2>/dev/null && \
    echo "  voted YES from $(cast wallet address --private-key "$VK")" || \
    echo "  skipped $(cast wallet address --private-key "$VK") (not on committee)"
done
```

Check vote counts:

```bash
cast call "$ENGINE" "votesOf(uint256)(uint256,uint256)" "$CLAIM_ID" --rpc-url "$RPC"
# Returns: (yesVotes, noVotes) — expect (7, 0)
```

---

## Step 7 — Finalize

The vote window is **24 hours**. After it expires, anyone can finalize.

```bash
# Check deadline
DEADLINE=$(cast call "$ENGINE" "voteDeadline(uint256)(uint256)" "$CLAIM_ID" --rpc-url "$RPC")
NOW=$(date +%s)
echo "deadline = $DEADLINE  now = $NOW"

# Once NOW > DEADLINE:
cast send "$ENGINE" "finalize(uint256)" "$CLAIM_ID" \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY"
```

Verify:

```bash
cast call "$ENGINE" "claimStatus(uint256)(uint8)" "$CLAIM_ID" --rpc-url "$RPC"
# Expected: 3 (FINALIZED_ACCEPT)
```

---

## Step 8 — Verify the attestation

### 8a — CLI query

```bash
skr query "$DEPLOYER"
```

Expected output: APPLIED_MATH domain score = 1000 (the signal weight of the math challenge).

### 8b — cast query via QueryGateway

```bash
cast call "$GATEWAY" "verify(address)(uint256[4])" "$DEPLOYER" --rpc-url "$RPC"
# Returns: [ALGO, FORMAL_VER, APPLIED_MATH, SEC_CODE]
# Expected: [0, 0, 1000000000000000000000, 0]
```

### 8c — Frontend /me page

1. Open the Vercel URL (or `pnpm dev` locally in `app/`).
2. Connect the deployer wallet (Base Sepolia network).
3. Navigate to `/me`.
4. Confirm: APPLIED_MATH score is non-zero.

### 8d — Basescan

1. Go to `https://sepolia.basescan.org/address/<AttestationStore_address>`.
2. Click **Internal Txns** or **Events**.
3. Find the `AttestationRecorded` event with the deployer address and challenge ID 1.

Or query directly:

```bash
STORE=$(python3 -c "import json; print(json.load(open('$DEPLOY'))['contracts']['AttestationStore'])")
cast logs --address "$STORE" --rpc-url "$RPC" --from-block 0
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `drawCommittee` reverts | Wait 4+ blocks after submission. Ensure 7 validators bonded **before** the claim was submitted. |
| `vote` reverts with "not member" | Only 7 of your validators are drawn. Non-members revert — this is expected. |
| `finalize` reverts | Vote window (24h) hasn't expired yet. Check `voteDeadline`. |
| APPLIED_MATH score = 0 on /me | Ensure `app/.env.local` has correct `NEXT_PUBLIC_QUERY_GATEWAY` and rebuild: `cd app && pnpm build`. |
| Proof verification fails | Regenerate proof with correct `bindingHash` — it must match `msg.sender` + `challengeId`. |
