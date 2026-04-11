# SkillRoot v0 — Architecture

## Topology

```
                      ┌─────────────────────┐
                      │     claimant        │
                      │  (wallet, browser)  │
                      └──────────┬──────────┘
                                 │ 1. skr solve / ProofUpload
                                 ▼
                      ┌─────────────────────┐
                      │    skr CLI / dApp   │
                      │  wagmi + viem +     │
                      │  snarkjs prover     │
                      └──────────┬──────────┘
                                 │ 2. submitClaim(proof, pub, cid)
                                 ▼
 ┌──────────────┐        ┌─────────────────────┐        ┌────────────────┐
 │ChallengeReg  │◄──────▶│   AttestationEngine │◄──────▶│  StakingVault  │
 │ (active lst) │        │   (orchestrator)    │        │  bond/slash    │
 └──────────────┘        └──────┬──────────────┘        └────────────────┘
                                │  3. verify via adapter
                                ▼
                      ┌─────────────────────┐
                      │  MathVerifier       │  snarkjs-emitted Groth16
                      │  Adapter → inner    │  (src/verifiers/)
                      └──────────┬──────────┘
                                 │ 4. draw committee (future blockhash)
                                 ▼
                      ┌─────────────────────┐
                      │     Sortition       │  stake-weighted sampling
                      └──────────┬──────────┘
                                 │ 5. commit drawn committee
                                 ▼
 ┌──────────────┐        ┌─────────────────────┐
 │  skr         │───────▶│   AttestationEngine │
 │  validate    │  vote  │   .vote(claimId, y) │
 │ (daemon)     │        └──────┬──────────────┘
 └──────────────┘               │ 6. finalize
                                ▼
                      ┌─────────────────────┐
                      │  AttestationStore   │  decayed scores / records
                      └──────────┬──────────┘
                                 │
                                 ▼
                      ┌─────────────────────┐
                      │    QueryGateway     │ ← dApps / wallets / UI
                      └─────────────────────┘
```

## Components

| Contract | Role |
|----------|------|
| **SKRToken** | Fixed-supply ERC20Votes governance token. 100M minted at genesis, no inflation. Slashing burns to `0xdead`. |
| **StakingVault** | Bond/unbond/slash. Dense 1-indexed validator array for O(k·n) sortition. 14-day unbond delay. |
| **ChallengeRegistry** | Full lifecycle (propose→activate/reject→deprecate). 10k SKR proposer bond. MVP seeds only 1 challenge but the API is live. |
| **Sortition** | Stake-weighted committee draw (size 7) via `blockhash(submissionBlock + 4)`. 240-block reveal window. |
| **AttestationEngine** | Submit / vote / finalize orchestrator. Computes `bindingHash = keccak256(abi.encode(msg.sender, challengeId)) & MASK248` contract-side and prepends it as public signal 0 — the **D2 revision**. |
| **AttestationStore** | Per-claimant record list + decayed score lookup per domain. Discrete half-life formula. Write-gated on Engine. |
| **QueryGateway** | Stable read surface for dApps; wraps `AttestationStore.scoresOf`. |
| **Governance** | Minimal on-chain propose/vote/execute using ERC20Votes snapshots. 4% quorum, 5-day voting period. No timelock in v0. |
| **MathVerifierAdapter** | Bridges the snarkjs-emitted fixed-size verifier (4 public signals) to the dynamic `IZKVerifier` interface. |

## D2 Claimant-Binding Revision

v0 takes a conscious shortcut: it does **not** run keccak inside a Circom circuit. Instead:

1. AttestationEngine computes `bindingHash = keccak256(abi.encode(msg.sender, challengeId)) & MASK248`
2. Engine prepends `bindingHash` to `circuitSignals` before calling the verifier
3. Circuits publish `bindingHash` as their first public signal (pass-through template)
4. The on-chain Groth16 check pins the hash to the proof

Benefit: circuits stay small (math.circom = 8.6k constraints) — adding a keccak gadget would blow that to ~100k+.

Cost: the claimant→proof binding lives at the contract layer, not the cryptographic layer. An attacker who modifies AttestationEngine could break binding, but any such modification would also break the governance-controlled verifier address, which is tamper-evident on-chain.

## Trust assumptions (v0)

- **Trusted setup**: single-party phase 2 contribution over Hermez's public phase 1 (pot14). Documented entropy; external contributions solicited pre-mainnet (see `threat-model.md`).
- **Sequencer liveness**: Base sequencer is trusted for inclusion within 24h. Reveal window is 240 L2 blocks ≈ 8 min.
- **No audit**: testnet only. `threat-model.md` enumerates known issues.
- **Genesis governance**: deployer initially holds governance; must be transferred to a multi-sig or the `Governance` contract before mainnet.
