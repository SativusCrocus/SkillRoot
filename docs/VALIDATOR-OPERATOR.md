---
title: SkillRoot Fraud-Prover Operator Guide
audience: external stakers onboarding under the v0.2.0-no-vote testnet
scope: Base Sepolia (v0 testnet only)
---

# Fraud-Prover Operator Guide (v0.2.0-no-vote)

v0.2.0-no-vote replaced the validator committee with a 24h fraud-proof window. There are no votes to cast. The operator role is now: **bond stake, watch pending claims, submit a fraud proof if you see an invalid one**. Any bonded staker is eligible — there is no committee sampling.

This guide walks a new operator through running that flow end-to-end on Base Sepolia. It assumes:

- You've been granted or purchased ≥1,000 SKR on Base Sepolia
- You have a wallet whose private key you control
- You run macOS or Linux with a reasonable uplink
- You're comfortable on the command line

> **v0 disclaimer:** SkillRoot v0 is an unaudited testnet prototype. Bond only testnet value. Read `docs/threat-model.md` before proceeding. Do not run with real assets.

## 1. Install the toolchain

```bash
git clone https://github.com/SativusCrocus/SkillRoot.git
cd SkillRoot
./scripts/setup.sh
```

`setup.sh` is idempotent. It installs Foundry, Node 20, pnpm 9, Rust, Circom 2, and snarkjs 0.7.

Sanity check:

```bash
forge --version
node --version     # v20.x or higher
pnpm --version     # 9.x or higher
snarkjs --version
circom --version
```

## 2. Build the CLI

```bash
cd cli
pnpm install
pnpm build
pnpm link --global
skr --help
```

You should see the subcommands: `challenges`, `solve`, `submit`, `dispute`, `query`, `stake`.

## 3. Configure the deployment target

The CLI reads a deployment JSON listing the contract addresses for the target network. For Base Sepolia, that file is at `deployments/base-sepolia.json`.

```bash
export PRIVATE_KEY=0x...                                  # your operator key
export SKR_CHAIN_ID=84532                                 # Base Sepolia
export SKR_RPC_URL=https://sepolia.base.org               # or your own RPC
export SKR_DEPLOYMENT="$(pwd)/deployments/base-sepolia.json"
```

Persist these in your shell profile (`~/.zshrc` / `~/.bashrc`) or a local `.envrc` with direnv. **Never commit your private key.**

## 4. Fund your address

1. **Base Sepolia ETH** for gas. Use [Alchemy](https://www.alchemy.com/faucets/base-sepolia), [QuickNode](https://faucet.quicknode.com/base/sepolia), or the Coinbase faucet.
2. **SKR** for bonding. Bond at least 1,000 SKR to be eligible to submit fraud proofs.

Verify:

```bash
cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $SKR_RPC_URL --ether
cast call $(jq -r '.contracts.SKRToken' $SKR_DEPLOYMENT) \
  "balanceOf(address)(uint256)" \
  $(cast wallet address --private-key $PRIVATE_KEY) \
  --rpc-url $SKR_RPC_URL
```

## 5. Bond

Minimum stake is **1,000 SKR** — the `FRAUD_PROVER_MIN_STAKE` threshold enforced inside `AttestationEngine.submitFraudProof`.

```bash
skr stake 1000
```

This does two transactions:
1. `SKRToken.approve(StakingVault, 1000e18)`
2. `StakingVault.bond(1000e18)`

## 6. Watch for pending claims

The minimal loop: subscribe to `ClaimSubmitted` events on `AttestationEngine`, and for each claim decide whether you can prove it's invalid inside its 24h fraud window. If yes, generate a fraud proof off-chain and submit it with `skr dispute`.

A reference fraud-watcher daemon is a P0 item on `ROADMAP.md`. Until it ships you can use a simple log-scan loop:

```bash
cast logs \
  --rpc-url $SKR_RPC_URL \
  --address $(jq -r '.contracts.AttestationEngine' $SKR_DEPLOYMENT) \
  "ClaimSubmitted(uint256,uint256,address,uint64,uint64,uint256,bytes32)" \
  --from-block latest
```

For each claimId surfaced, read the claim back:

```bash
cast call $(jq -r '.contracts.AttestationEngine' $SKR_DEPLOYMENT) \
  "getClaim(uint256)((uint256,uint256,address,uint64,uint64,uint256,bytes32,uint8))" \
  $CLAIM_ID --rpc-url $SKR_RPC_URL
```

## 7. Submitting a fraud proof

If you can demonstrate the claim's statement is false, generate a fraud proof against the fraud circuit and submit it:

```bash
skr dispute --claim $CLAIM_ID --calldata ./path/to/fraud-calldata.json
```

This call checks your stake ≥ `FRAUD_PROVER_MIN_STAKE`, binds the fraud proof to `(claimant, challengeId)` via D2, and verifies the Groth16 proof on-chain. On success: 50% of the 100 SKR bond is sent to you, 50% is burned.

If the fraud window expires with no successful proof, anyone can call `finalizeClaim(claimId)` to auto-accept. The claim bond is returned to the claimant and the attestation is recorded.

## 8. Unbonding

```bash
cast send $(jq -r '.contracts.StakingVault' $SKR_DEPLOYMENT) \
  "requestUnbond(uint256)" 1000000000000000000000 \
  --rpc-url $SKR_RPC_URL --private-key $PRIVATE_KEY

# Wait 14 days
cast send $(jq -r '.contracts.StakingVault' $SKR_DEPLOYMENT) \
  "withdraw()" \
  --rpc-url $SKR_RPC_URL --private-key $PRIVATE_KEY
```

Partial unbonds must leave ≥1,000 SKR or you must fully exit.

## 9. Known v0 rough edges

From `docs/threat-model.md`:

1. **Single-party trusted setup** — Phase 2 was run by the v0 deployer alone for both the claim and fraud circuits. Pre-mainnet, a ≥3-party ceremony will re-deploy both verifiers.
2. **One circuit pair only** — modexp (+ its fraud dual) is the sole domain. Three more (`algo`, `fv`, `sec`) ship in v1, each with a paired fraud circuit.
3. **Fraud-watcher liveness** — if no staker produces a fraud proof inside 24h, an invalid claim auto-finalizes. Mitigated by multiple independent operators monitoring.
4. **No fee market** — v0 operators earn only through successful fraud proofs (50 SKR each). The fee market for accepted-claim sharing lands in v1.

## Appendix: troubleshooting

**`dispute` reverts with `ProverUnderstaked`**
→ Your bonded stake is below 1,000 SKR. Top up via `skr stake <amount>`.

**`dispute` reverts with `ChallengeWindowClosed`**
→ The 24h fraud window has already elapsed. If it hasn't been finalized yet, `finalizeClaim` will accept the claim on the next call from anyone.

**`dispute` reverts with `InvalidFraudProof`**
→ Your fraud proof didn't verify under `FraudGroth16Verifier`. Double-check the public signals; recall signal 0 must be `bindingHashOf(claimant, challengeId)` (computed against the **claim's** claimant, not your own address).

**`approve` tx pending forever**
→ Base Sepolia occasionally has slow blocks. Retry with a higher gas price via `--gas-price`. Check https://sepolia.basescan.org.
