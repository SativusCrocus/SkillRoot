# First Attestation on Base Sepolia (v0.2.0-no-vote)

End-to-end: solve modexp → submit proof with 100 SKR bond → wait out the 24h fraud window → anyone calls `finalizeClaim` → verify the attestation.

---

## Live record

The first attestation under the v0.2.0-no-vote architecture on Base Sepolia:

| Field | Value |
|-------|-------|
| Network           | Base Sepolia (chain 84532) |
| Version           | v0.2.0-no-vote |
| Challenge         | APPLIED_MATH #1 — modular exponentiation |
| Proof statement   | `3^7 mod 13 = 3` (Groth16, BN254) |
| Bond              | 100 SKR locked at submit, returned on finalize |
| Fraud window      | 24 hours — closed with no challenge |
| Submission tx     | [`0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9`](https://sepolia.basescan.org/tx/0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9) |
| Submission block  | 40292380 |
| Status            | `FINALIZED_ACCEPT` |
| APPLIED_MATH score | time-decayed signal weight |
| Proof artifacts   | [`proofs/input-1.json`](../proofs/input-1.json), [`proofs/calldata-1.json`](../proofs/calldata-1.json) |
| Engine            | [`0xF2541F68f47f5aB978979B5Ab766f08750d915e8`](https://sepolia.basescan.org/address/0xF2541F68f47f5aB978979B5Ab766f08750d915e8) |

---

## Manual walkthrough

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
echo "engine   = $ENGINE"
```

---

## Step 1 — Fund the claimant

Base Sepolia faucet: <https://www.coinbase.com/faucets/base-ethereum-goerli-faucet>

Request 0.05 ETH to the claimant address, and ensure the claimant holds at least 100 SKR (the `CLAIM_BOND`):

```bash
cast balance "$DEPLOYER" --rpc-url "$RPC"
cast call "$TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url "$RPC"
```

---

## Step 2 — Solve the modexp challenge

Pick parameters. The proof demonstrates knowledge of `exponent` such that `base^exponent mod modulus == result`.

| Param | Value | Visibility |
|-------|-------|------------|
| base     | 3  | public |
| exponent | 7  | **private** |
| modulus  | 13 | public |
| result   | 3  | public (3^7 mod 13 = 3) |

```bash
export SKR_RPC_URL="$RPC"
export SKR_CHAIN_ID=84532

skr solve 1 \
  --base 3 --exp 7 --mod 13 \
  --wasm ./circuits/math/build/math_js/math.wasm \
  --zkey ./circuits/math/build/math_final.zkey \
  --out ./proofs
```

Output: `./proofs/calldata-1.json` — ready for on-chain submission.

---

## Step 3 — Approve + submit

`submitClaim` pulls 100 SKR from the claimant as the claim bond. Approve first:

```bash
cast send "$TOKEN" "approve(address,uint256)" "$ENGINE" "100000000000000000000" \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY"
```

Then submit via CLI:

```bash
skr submit ./proofs/calldata-1.json --challenge 1
# Returns claimId (= 1 on a fresh deployment)
```

Record the claimId:

```bash
CLAIM_ID=$(cast call "$ENGINE" "nextClaimId()(uint256)" --rpc-url "$RPC")
CLAIM_ID=$((CLAIM_ID - 1))
echo "claimId = $CLAIM_ID"
```

---

## Step 4 — Wait out the 24h fraud window

Any bonded staker with ≥ 1,000 SKR can submit a fraud proof inside this window. If no valid fraud proof lands, the claim auto-accepts.

```bash
cast call "$ENGINE" \
  "getClaim(uint256)((uint256,uint256,address,uint64,uint64,uint256,bytes32,uint8))" \
  "$CLAIM_ID" --rpc-url "$RPC"
# challengeDeadline is field[4]; status is field[7] (0 = PENDING)
```

No action is needed on your side during the window — just wait.

---

## Step 5 — Finalize

Once the window closes, anyone can call `finalizeClaim`:

```bash
cast send "$ENGINE" "finalizeClaim(uint256)" "$CLAIM_ID" \
  --rpc-url "$RPC" --private-key "$PRIVATE_KEY"
```

Verify:

```bash
cast call "$ENGINE" \
  "getClaim(uint256)((uint256,uint256,address,uint64,uint64,uint256,bytes32,uint8))" \
  "$CLAIM_ID" --rpc-url "$RPC"
# Expected status = 1 (FINALIZED_ACCEPT)
```

---

## Step 6 — Verify the attestation

### CLI query

```bash
skr query "$DEPLOYER"
```

Expected output: APPLIED_MATH domain score ≈ the signal weight of challenge #1.

### Direct QueryGateway call

```bash
cast call "$GATEWAY" "verify(address)(uint256[4])" "$DEPLOYER" --rpc-url "$RPC"
# Returns [ALGO, FORMAL_VER, APPLIED_MATH, SEC_CODE]
```

### Frontend /me page

1. Open the Vercel URL or `pnpm dev` locally.
2. Connect the claimant wallet (Base Sepolia network).
3. Navigate to `/me`.
4. Confirm APPLIED_MATH score is non-zero.

### Basescan

`https://sepolia.basescan.org/address/<AttestationStore_address>` → **Events** → find the attestation-recorded log for your address + challenge 1.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `submitClaim` reverts `ChallengeNotActive` | Challenge #1 must be ACTIVE. Check `getChallenge(1)` on the registry. |
| `submitClaim` reverts `InvalidProof` | Regenerate with the correct `bindingHash`; it must match `bindingHashOf(msg.sender, challengeId)`. |
| `submitClaim` reverts `ERC20InsufficientAllowance` | Approve 100 SKR to the engine before submitting. |
| `finalizeClaim` reverts `ChallengeWindowOpen` | 24 hours haven't elapsed yet. Wait until `challengeDeadline`. |
| `submitFraudProof` reverts `ProverUnderstaked` | Fraud prover needs ≥ 1,000 SKR bonded via StakingVault. |
| APPLIED_MATH score = 0 on /me | Ensure `app/.env.local` has correct `NEXT_PUBLIC_QUERY_GATEWAY` and rebuild: `cd app && pnpm build`. |
