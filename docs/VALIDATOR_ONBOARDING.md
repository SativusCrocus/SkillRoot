# SkillRoot v0.2.0-no-vote — Fraud-Prover Onboarding (Base Sepolia)

v0.2.0-no-vote has no validator committee. The "validator" role is now a **fraud-prover**: bond stake, watch pending claims, and submit a fraud proof if you see an invalid one. Any bonded staker is eligible — no committee sampling, no voting window.

**Chain:** Base Sepolia (84532)
**Minimum stake:** 1,000 SKR (`FRAUD_PROVER_MIN_STAKE`)
**Fraud window:** 24 hours after each claim submission
**Reward per successful fraud proof:** 50 SKR (half the claimant's bond)

---

## Prerequisites

| Tool | Install |
|------|---------|
| Node.js >= 20 | `curl -fsSL https://fnm.vercel.app/install \| bash && fnm install 20` |
| pnpm >= 9 | `npm i -g pnpm@9` |
| Foundry (cast) | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| Git | system default |

---

## Step 1 — Generate your operator key

```bash
cast wallet new

# Output:
#   Address:     0xYOUR_ADDRESS
#   Private key: 0xYOUR_PRIVATE_KEY

export PRIVATE_KEY=0xYOUR_PRIVATE_KEY
export OPERATOR_ADDR=$(cast wallet address --private-key $PRIVATE_KEY)
echo "operator: $OPERATOR_ADDR"
```

Fund the address with Base Sepolia ETH and SKR. ETH via the [Alchemy Base Sepolia faucet](https://www.alchemy.com/faucets/base-sepolia); SKR via faucet or direct transfer. You need ≥ 1,000 SKR to bond.

Verify:

```bash
export RPC=https://sepolia.base.org

cast balance $OPERATOR_ADDR --rpc-url $RPC

cast call 0xebEB1dAC3F774b47e28844D1493758838D8463B2 \
  "balanceOf(address)(uint256)" $OPERATOR_ADDR --rpc-url $RPC
```

---

## Step 2 — Clone repo and build the CLI

```bash
git clone https://github.com/SativusCrocus/SkillRoot.git
cd SkillRoot
pnpm install
pnpm -C cli build
```

The repo ships `deployments/base-sepolia.json` with the current v0.2.0-no-vote contract addresses. Point your shell at it:

```bash
export SKR_CHAIN_ID=84532
export SKR_RPC_URL=$RPC
export SKR_DEPLOYMENT="$(pwd)/deployments/base-sepolia.json"
```

Verify the CLI loads:

```bash
skr challenges
# Should list challenge #1 (APPLIED_MATH, ACTIVE)
```

---

## Step 3 — Bond 1,000 SKR

```bash
skr stake 1000
```

Expected output:

```
balance: 1000.0 SKR
✔ approved 0x...
✔ bonded in block 123456
stake: 1000.0 SKR
```

Confirm on-chain:

```bash
cast call 0x8CCdc62e5762f89d0D17fc5e55Ae3555c207Ad6b \
  "stakeOf(address)(uint256)" $OPERATOR_ADDR --rpc-url $RPC
```

---

## Step 4 — Watch for claims

There is **no daemon to run** in v0.2.0-no-vote. Stakers watch the engine directly:

```bash
cast logs \
  --rpc-url $RPC \
  --address 0xF2541F68f47f5aB978979B5Ab766f08750d915e8 \
  "ClaimSubmitted(uint256,uint256,address,uint64,uint64,uint256,bytes32)" \
  --from-block latest
```

For each claim, fetch its details:

```bash
cast call 0xF2541F68f47f5aB978979B5Ab766f08750d915e8 \
  "getClaim(uint256)((uint256,uint256,address,uint64,uint64,uint256,bytes32,uint8))" \
  $CLAIM_ID --rpc-url $RPC
```

Check `challengeDeadline` — you have until that timestamp to submit a fraud proof if the claim is invalid.

---

## Step 5 — Submit a fraud proof (when needed)

If you can prove a claim's statement is false, generate a fraud proof off-chain against `fraud.circom` and submit:

```bash
skr dispute --claim $CLAIM_ID --calldata ./fraud-calldata.json
```

The engine:
1. Checks your stake ≥ 1,000 SKR
2. Binds the fraud proof to the claim's `(claimant, challengeId)` via D2
3. Verifies the Groth16 fraud proof on-chain
4. Transfers 50 SKR to you, burns 50 SKR, marks the claim `FINALIZED_REJECT`

If the fraud window closes with no valid fraud proof, anyone can call:

```bash
cast send 0xF2541F68f47f5aB978979B5Ab766f08750d915e8 \
  "finalizeClaim(uint256)" $CLAIM_ID \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

The claim bond is returned to the claimant and the attestation is recorded.

---

## Contract Addresses (Base Sepolia — v0.2.0-no-vote)

| Contract | Address |
|----------|---------|
| SKRToken              | `0xebEB1dAC3F774b47e28844D1493758838D8463B2` |
| StakingVault          | `0x8CCdc62e5762f89d0D17fc5e55Ae3555c207Ad6b` |
| AttestationStore      | `0x3b6a969DCAD3d79164dA2AD75c2191350BF536a8` |
| ChallengeRegistry     | `0xbD13B7822bBc4cC6C0C53CA08497643C6085294B` |
| AttestationEngine     | `0xF2541F68f47f5aB978979B5Ab766f08750d915e8` |
| QueryGateway          | `0xe4A4c37B59F29807840b1DB22C45C66dcB5D01A2` |
| MathGroth16Verifier   | `0x8176831054075DaF6B26783491a04D3C14eFD41b` |
| MathVerifierAdapter   | `0xde605f7BA61030916136f079731260B76bE8074C` |
| FraudGroth16Verifier  | `0x1E39641eaf3930d19F8619184aE10b4f38a5a5bB` |
| FraudVerifierAdapter  | `0x173241d25feb42EA8D9D3D4c767788c6F23C62A7` |

## Unbonding

```bash
cast send 0x8CCdc62e5762f89d0D17fc5e55Ae3555c207Ad6b \
  "requestUnbond(uint256)" "1000000000000000000000" \
  --rpc-url $RPC --private-key $PRIVATE_KEY

# Wait 14 days
cast send 0x8CCdc62e5762f89d0D17fc5e55Ae3555c207Ad6b \
  "withdraw()" \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

Partial unbonds must leave ≥ 1,000 SKR or you must fully exit.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `insufficient balance` on stake | Acquire more SKR (faucet or direct transfer) |
| `BelowMinStake` revert | A single `bond()` must bring you to ≥ 1,000 SKR total |
| `dispute` reverts `ProverUnderstaked` | Your bonded stake is below 1,000 SKR — top up with `skr stake` |
| `dispute` reverts `ChallengeWindowClosed` | The 24h window has elapsed — anyone can now `finalizeClaim` |
| `dispute` reverts `InvalidFraudProof` | Fraud proof didn't verify — recheck public signal 0 = `bindingHashOf(claimant, challengeId)` |
