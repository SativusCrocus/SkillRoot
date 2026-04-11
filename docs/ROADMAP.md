---
title: SkillRoot Roadmap
scope: post-v0
---

# ROADMAP

v0 is the minimum surface area that proves the SkillRoot primitive: one circuit, one active challenge, a single CLI validator, no timelock, single-party phase-2 ceremony, testnet only. This document lists the deferred items that v1 — and beyond — should address, with priority and rationale.

## Legend

| Priority | Meaning |
|----------|---------|
| **P0** | Blocking mainnet. Must land before real-value deployment. |
| **P1** | High value, non-blocking for testnet. Ships in v1. |
| **P2** | Nice to have / research track. |

## v1 scope (P0 + P1)

### P0 — mainnet prerequisites

#### Multi-party phase 2 trusted setup ceremony
**Status**: deferred from v0 (single-party contribution in `circuits/math/build.sh`).
**Deliverable**: ≥3 independent external contributors to the Groth16 phase 2, each publishing their entropy commitment. Replace the verifier contract in the existing verifier-adapter slot. Documented in `threat-model.md` R4.
**Blocker for**: any mainnet deploy.

#### TimelockController on Governance
**Status**: `Governance.sol` executes the instant voting ends in v0.
**Deliverable**: wrap the governance executor in an OpenZeppelin `TimelockController`, default delay 48h, admin-rotatable by governance itself. Update `Deploy.s.sol` and the 5-signer multi-sig bootstrap handoff.
**Blocker for**: any mainnet deploy. Threat-model R6.

#### Professional audit
**Status**: v0 is explicitly unaudited.
**Deliverable**: engagement with a reputable ZK-aware audit firm covering:
1. `AttestationEngine.sol` (D2 binding, committee flow, slash math)
2. `Sortition.sol` (stake-weighted draw correctness under edge cases)
3. `StakingVault.sol` (reentrancy, burn accounting)
4. `Governance.sol` (proposal lifecycle, quorum math)
5. `math.circom` (constraint soundness, range-check tightness)
6. trusted setup artifacts and phase 2 ceremony transcript
**Blocker for**: mainnet deploy.

#### VRF-backed committee randomness
**Status**: v0 uses `blockhash(submissionBlock + 4)`, vulnerable to sequencer grinding.
**Deliverable**: swap `Sortition.sol` entropy source to Chainlink VRF v2.5 (or drand via a bridge). Keep the existing 240-block reveal window semantics.
**Blocker for**: mainnet deploy. Threat-model R3.

### P1 — v1 scope, non-blocking

#### Additional circuits
v0 ships **one** circuit (`math`). v1 adds three more to cover the four domain enum values:

| Slug | Domain | Statement | Approx. constraints | Notes |
|------|--------|-----------|---------------------|-------|
| `algo` | `ALGO` | Prove knowledge of a `Vec<u32>` that sorts to a target under a committed comparator count budget | ~30k | Demonstrates imperative algorithm correctness |
| `fv` | `FORMAL_VER` | Prove a SAT instance satisfies a committed CNF formula | ~15k | Gateway to formal verification claims |
| `sec` | `SEC_CODE` | Prove knowledge of an input that triggers a known vulnerability pattern in a committed bytecode fragment | ~50k | Requires a small EVM-interpreter subset in-circuit |

Each circuit ships its own `*Verifier.sol` + `*VerifierAdapter.sol` and reuses `BindingPassthrough` for the D2 binding. `ChallengeRegistry` already supports multi-challenge activation.

#### Fee market
v0 has no direct validator rewards (bootstrap grants only). v1 introduces:
- A per-claim submission fee paid in SKR by the claimant
- 70% distributed pro-rata to YES voters on accepted claims, 30% burned
- Governance-adjustable BPS split

Open question: whether the fee is paid to the engine escrow or directly to voters at `finalize` time. Gas-cost vs. incentive-precision tradeoff.

#### Browser-side proof generation
v0 frontend uploads a pre-generated proof JSON (user runs `skr solve` locally). v1:
- Ship `snarkjs.groth16.fullProve` inside the Next.js bundle
- Web Worker wrapping so it doesn't block the UI thread
- WASM witness generator (already Circom's default) loaded on demand
- Progress bar tied to proof stages

Bundle-size budget: +2.5 MB gzipped. Defer behind a dynamic `import()` on `/submit`.

#### Arweave artifact mirror
v0 stores proof-supporting artifacts on web3.storage (IPFS). v1 adds Arweave as a second pin via `ardrive-cli` or `@irys/sdk`, with `ChallengeRegistry.seedArtifact` accepting a dual CID. Claimants can continue to submit IPFS-only; the second pin is optional but recommended.

#### Governance UI
v0 users must use `cast send` or Tenderly to call `Governance.propose` / `Governance.execute`. v1 adds a governance tab to the Next.js app:
- Proposal list with state (Pending / Active / Passed / Executed)
- Inline vote buttons
- Text rendering of proposed calldata (4byte.directory integration)
- Quorum + for/against progress bars

Built with the existing `wagmi` + viem stack.

## v2 research track (P2)

- **Delegation**: validators run but SKR holders delegate voting power. Requires rewriting `StakingVault` to track delegator balances and introducing a delegation manager.
- **Recursive proofs**: aggregate N attestation proofs into one submission via SnarkPack or Nova/ProtoStar; amortizes on-chain verification gas to O(log N).
- **Cross-chain readers**: `QueryGateway` exposed via LayerZero or Chainlink CCIP so a score can be read from any EVM chain without rebridging SKR.
- **ZKML skill proofs**: prove model outputs match a committed dataset, enabling ML-engineering skill attestations. Depends on mature zkML frameworks (EZKL, Giza).
- **Non-EVM validators**: Move validator client to Rust for 10x performance headroom; keep CLI as a thin shell wrapper.
- **Reputation bonds**: stake amount scales with outstanding unresolved attestations, reducing grief vectors on high-claim-rate validators.
- **Appeals committee**: challenge-and-respond flow for disputed finalizations; slashed minority voters can stake on an appeal to reclaim stake (threat-model R10).
- **Mobile proof generation**: evaluate snarkjs / halo2 / Starky mobile feasibility; likely blocked on WASM-SIMD maturity on iOS.
- **Standalone validator daemon**: split `skr validate` into its own Rust binary with p2p gossip so committee members don't need to trust their own view of the chain.
- **Alternative proof systems**: benchmark Plonky3, Nova, Halo2 against Groth16 for the four domain circuits; Groth16's trusted setup is the main v0 liability.

## Explicitly out of scope

- **Bonding curves / AMMs / token launch mechanics**: SKR is not a tradable speculative asset in v0. No planned changes.
- **Liquid staking derivatives**: complexity vs. value tradeoff unfavorable.
- **Chain expansion beyond Base**: mainnet v1 ships on Base only; multi-chain is a v2 conversation at earliest.
- **Closed-source validator**: all validator code must remain open.

## Tracking

v1 items will be re-scoped into GitHub issues once the v0 testnet phase has run for ≥30 days and accumulated real operator feedback (per `bootstrapping.md` week 8 handoff). Issues will carry `v1:p0` and `v1:p1` labels matching this document.
