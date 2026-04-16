# SkillRoot v0.2.0-no-vote — Architecture

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
                                 │ 2. submitClaim(proof, pub, cid)  +  100 SKR bond
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
                                 │ 4. open 24h fraud window
                                 ▼
                      ┌─────────────────────┐
                      │  Fraud window open  │     any bonded staker
                      │  (24h countdown)    │ ──▶ submitFraudProof(claimId, π)
                      └──────────┬──────────┘     → bond split 50% prover / 50% burn
                                 │ 5. window closes, no valid fraud proof
                                 ▼
                      ┌─────────────────────┐
                      │  finalizeClaim()    │  permissionless
                      │  → bond returned    │
                      └──────────┬──────────┘
                                 │ 6. record attestation
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
| **SKRToken** | Fixed-supply ERC20 (extends ERC20Votes base for future governance hooks). 100M minted at genesis, no inflation. Slashing burns to `0xdead`. |
| **StakingVault** | Bond / unbond / slash. 1000 SKR minimum stake. 14-day unbond delay. Stake gates eligibility to submit fraud proofs. |
| **ChallengeRegistry** | Bonded proposal with permissionless rejection / activation after an inactivity window. No on-chain vote. 10k SKR proposer bond. |
| **AttestationEngine** | `submitClaim` → 24h fraud window → `submitFraudProof` **or** `finalizeClaim`. Computes `bindingHash = keccak256(abi.encode(msg.sender, challengeId)) & MASK248` contract-side and prepends it as public signal 0 for **both** claim proofs and fraud proofs — the D2 revision. |
| **AttestationStore** | Per-claimant record list + decayed score lookup per domain. Discrete half-life formula. Write-gated on Engine. |
| **QueryGateway** | Stable read surface for dApps; wraps `AttestationStore.scoresOf`. |
| **MathGroth16Verifier + MathVerifierAdapter** | Claim-side ZK verifier (snarkjs-emitted) + adapter bridging to the dynamic `IZKVerifier` interface. |
| **FraudGroth16Verifier + FraudVerifierAdapter** | Fraud-side ZK verifier + adapter. The engine's `fraudVerifier` is set at construction and is the only path to refute a pending claim. |

## Removed in v0.2.0-no-vote

The earlier draft included `Governance.sol`, `Sortition.sol`, and `ForgeGuard.sol`. All three were dropped because the fraud-proof + auto-finalize flow provides the same economic security with a strictly smaller attack surface:

- **No committee** → no sortition RNG, no `blockhash` grinding, no reveal window.
- **No votes** → no liveness slash, no equivocation slash, no 24h voting window to defend.
- **No governance** → no proposal queue, no quorum, no timelock debt, no deployer-privilege concentration.

## D2 Claimant-Binding Revision

v0 takes a conscious shortcut: it does **not** run keccak inside a Circom circuit. Instead:

1. AttestationEngine computes `bindingHash = keccak256(abi.encode(msg.sender, challengeId)) & MASK248`.
2. Engine prepends `bindingHash` to `circuitSignals` before calling the verifier.
3. Circuits publish `bindingHash` as their first public signal (pass-through template).
4. The on-chain Groth16 check pins the hash to the proof.

For fraud proofs the binding is computed against the **claim's** claimant+challengeId (not `msg.sender` of the fraud prover), so the fraud proof is cryptographically bound to the exact submission it refutes.

Benefit: circuits stay small (math.circom ≈ 8.6k constraints). Adding a keccak gadget would blow that to ~100k+.

Cost: the claimant→proof binding lives at the contract layer. An attacker who modifies AttestationEngine could break binding, but any such modification would require redeploying the engine (the deployed address is immutable and has no admin).

## Trust assumptions (v0)

- **Trusted setup**: single-party phase 2 contribution over Hermez's public phase 1 (pot14). Documented entropy; external contributions solicited pre-mainnet (see `threat-model.md`).
- **Sequencer liveness**: Base sequencer is trusted for inclusion within the 24h fraud window.
- **No audit**: testnet only. `threat-model.md` enumerates known issues.
- **Genesis key burned**: the deployer key used for initial deployment was burned after Challenge #1 was activated; no admin key exists on any contract.
