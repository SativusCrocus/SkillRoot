---
title: SkillRoot Roadmap
scope: post-v0.2.0-no-vote
---

# ROADMAP

v0.2.0-no-vote is the minimum surface area that proves the SkillRoot primitive: one claim circuit, one fraud circuit, one active challenge, a 24h fraud-proof window replacing the committee entirely, single-party phase-2 ceremony, testnet only. This document lists the deferred items that v1 — and beyond — should address, with priority and rationale.

## Status

- **v0.2.0-no-vote live on Base Sepolia** (chain 84532). 8 canonical contracts deployed, 1 challenge (APPLIED_MATH) active, dApp at [app-nine-rho-70.vercel.app](https://app-nine-rho-70.vercel.app). See [`deployments/base-sepolia.json`](../deployments/base-sepolia.json).
- **First attestation (v0.2.0-no-vote)** submitted under the fraud-proof flow: block 40292380, tx `0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9`. Claim auto-finalized after a 24h fraud window closed with no challenge.
- **Removed from earlier draft**: `Governance.sol`, `Sortition.sol`, `ForgeGuard.sol`. No committees, no on-chain votes. Rationale documented in [`docs/architecture.md`](architecture.md).
- **Next gate**: external fraud-watcher onboarding and ≥50 attestations before broader publicity.

## Legend

| Priority | Meaning |
|----------|---------|
| **P0** | Blocking mainnet. Must land before real-value deployment. |
| **P1** | High value, non-blocking for testnet. Ships in v1. |
| **P2** | Nice to have / research track. |

## v1 scope (P0 + P1)

### P0 — mainnet prerequisites

#### Multi-party phase 2 trusted setup ceremony
**Status**: deferred from v0 (single-party contribution in `circuits/*/build.sh`).
**Deliverable**: ≥3 independent external contributors to the Groth16 phase 2 for **both** the claim and fraud circuits, each publishing their entropy commitment. Replace the verifier contracts behind the adapter slots.
**Blocker for**: any mainnet deploy.

#### Professional audit
**Status**: v0 is explicitly unaudited.
**Deliverable**: engagement with a reputable ZK-aware audit firm covering:
1. `AttestationEngine.sol` (D2 binding, fraud-window accounting)
2. `StakingVault.sol` (reentrancy, burn accounting, fraud-prover stake gate)
3. `ChallengeRegistry.sol` (bonded proposal flow, permissionless activation timing)
4. `math.circom` and `fraud.circom` (constraint soundness, range-check tightness, duality)
5. trusted setup artifacts and phase 2 ceremony transcripts
**Blocker for**: mainnet deploy.

#### Fraud-watcher liveness
**Status**: v0 relies on one or more stakers running off-chain fraud-watchers.
**Deliverable**: write and publish a reference fraud-watcher daemon (Rust or TS) with documented uptime SLAs; run at least two independent instances during the bootstrap period. Threat-model R3.
**Blocker for**: mainnet deploy.

### P1 — v1 scope, non-blocking

#### Additional circuits
v0 ships **one active** claim circuit (`math`) + matching fraud circuit. v1 adds three more to cover the four domain enum values:

| Slug | Domain | Statement | Approx. constraints | Notes |
|------|--------|-----------|---------------------|-------|
| `algo` | `ALGO` | Prove knowledge of a `Vec<u32>` that sorts to a target under a committed comparator count budget | ~30k | Demonstrates imperative algorithm correctness |
| `fv` | `FORMAL_VER` | Prove a SAT instance satisfies a committed CNF formula | ~15k | Gateway to formal verification claims |
| `sec` | `SEC_CODE` | Prove knowledge of an input that triggers a known vulnerability pattern in a committed bytecode fragment | ~50k | Requires a small EVM-interpreter subset in-circuit |

Each circuit ships its own `*Verifier.sol` + `*VerifierAdapter.sol` **and** a paired fraud circuit, and reuses `BindingPassthrough` for the D2 binding. `ChallengeRegistry` already supports multi-challenge activation.

#### Browser-side proof generation
v0 frontend uploads a pre-generated proof JSON (user runs `skr solve` locally). v1:
- Ship `snarkjs.groth16.fullProve` inside the Next.js bundle
- Web Worker wrapping so it doesn't block the UI thread
- WASM witness generator loaded on demand
- Progress bar tied to proof stages

Bundle-size budget: +2.5 MB gzipped. Defer behind a dynamic `import()` on `/submit`.

#### Arweave artifact mirror
v0 stores proof-supporting artifacts on web3.storage (IPFS). v1 adds Arweave as a second pin via `ardrive-cli` or `@irys/sdk`, with `ChallengeRegistry.seedArtifact` accepting a dual CID.

#### Optional governance layer (deferred design)
If v1 reintroduces any on-chain parameter changes (fee splits, new domains, circuit rotation), it will be via a minimal ERC20Votes + TimelockController stack **sitting above** the existing contracts — the core engine will remain admin-less. No upgrade proxy.

## v2 research track (P2)

- **Recursive proofs**: aggregate N attestation proofs into one submission via SnarkPack or Nova/ProtoStar; amortizes on-chain verification gas to O(log N).
- **Cross-chain readers**: `QueryGateway` exposed via LayerZero or Chainlink CCIP so a score can be read from any EVM chain without rebridging SKR.
- **ZKML skill proofs**: prove model outputs match a committed dataset, enabling ML-engineering skill attestations. Depends on mature zkML frameworks (EZKL, Giza).
- **Reputation bonds**: scale claim-bond size with a claimant's outstanding unresolved attestations, reducing grief vectors.
- **Mobile proof generation**: evaluate snarkjs / halo2 / Starky mobile feasibility; likely blocked on WASM-SIMD maturity on iOS.
- **Alternative proof systems**: benchmark Plonky3, Nova, Halo2 against Groth16; Groth16's trusted setup is the main v0 liability.

## Explicitly out of scope

- **Bonding curves / AMMs / token launch mechanics**: SKR is not a tradable speculative asset in v0. No planned changes.
- **Liquid staking derivatives**: complexity vs. value tradeoff unfavorable.
- **Chain expansion beyond Base**: mainnet v1 ships on Base only; multi-chain is a v2 conversation at earliest.
- **Closed-source tooling**: all tooling must remain open.

## Tracking

v1 items will be re-scoped into GitHub issues once the v0.2.0-no-vote testnet phase has run for ≥30 days and accumulated real operator feedback. Issues will carry `v1:p0` and `v1:p1` labels matching this document.
