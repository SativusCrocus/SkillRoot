# Threat Model — SkillRoot v0

**Scope**: testnet only (Base Sepolia). This document enumerates known risks and explicitly does *not* claim production readiness.

## Disclaimer

SkillRoot v0 is an unaudited prototype. Do **not** use real assets or rely on SkillRoot attestations for any high-stakes decision. The trusted setup ceremony is single-party. Governance has no timelock.

## Attack surface

### 1. Sybil attacks on the validator set

**Risk**: Attacker creates many low-stake validators to bias committee draws.

**Mitigation**: Stake-weighted sortition, not per-address. Min stake 1,000 SKR. Attacker's expected committee fraction equals their stake fraction, not their address count.

**Residual risk**: At small `n` (early network), even a small capital outlay can yield outsized committee representation. Bootstrapping limits this by distributing operator grants.

### 2. Committee collusion

**Risk**: 5 out of 7 committee members collude to accept a bogus claim.

**Mitigation**:
- 5% equivocation slash on each wrong voter if the true outcome is later challenged
- Committee draw is randomized per-claim, so collusion must persist across many draws
- Real Groth16 verification at the contract layer: colluders still need to submit a mathematically valid proof, not just lie about it

**Residual risk**: If all 7 happen to be colluders and the proof itself is valid (e.g. a real but low-effort modexp), nothing stops them accepting it. Mitigation: deprecate the challenge, which doesn't invalidate past records but halts future accruals. Governance can shorten the reveal window in an emergency.

### 3. Committee pre-draw manipulation (blockhash grinding)

**Risk**: A claimant-friendly actor manipulates `blockhash(submissionBlock + 4)` by controlling the sequencer.

**Mitigation**:
- Base's sequencer is centralized today but blockhash manipulation would be publicly observable
- 4-block delay is short enough that grinding on L2 is impractical for non-sequencer actors
- Reveal window = 240 blocks (~8 min) forces a resubmit if the draw is missed, adding a retry cost

**Residual risk**: If the Base sequencer is compromised, an attacker can pre-compute committees. Mitigation is to migrate to a VRF (Chainlink, drand) before mainnet — documented in `ROADMAP.md`.

### 4. Single-party trusted setup

**Risk**: Whoever ran phase 2 could retain toxic waste and forge proofs.

**Mitigation**: Phase 1 uses Hermez's publicly audited Powers of Tau ceremony. Phase 2 entropy is documented and the contribution hash is published in `build/verification_key.json`.

**Residual risk**: Phase 2 is single-party. Before any mainnet deployment, a multi-party phase 2 ceremony with ≥3 independent contributors must be run and the verifier redeployed.

### 5. D2 binding revision

**Risk**: The claimant binding lives at the contract layer (`keccak256(abi.encode(msg.sender, challengeId)) & MASK248`), not inside the ZK circuit. A malicious AttestationEngine upgrade could weaken it.

**Mitigation**:
- AttestationEngine is non-upgradeable in v0
- Governance cannot change the binding formula without deploying a new Engine, which is publicly observable
- 248-bit mask still provides 248 bits of collision resistance

**Residual risk**: Future upgradeability could reintroduce this risk. v1's audit scope should include governance-controlled engine upgrades.

### 6. Governance capture

**Risk**: An attacker accumulates enough SKR to hit the 4% quorum and pass malicious proposals.

**Mitigation**:
- 5-day voting period gives time to react
- `Deploy.s.sol` transfers all 100M SKR to the Governance contract at genesis — reducing holder concentration
- Multi-sig control of the Governance contract during bootstrap (weeks 7–8)

**Residual risk**: No timelock. A malicious proposal can execute the instant voting ends. **v1 must add a TimelockController.**

### 7. Front-running submitClaim

**Risk**: A mempool observer copies a pending claim's proof and submits it with their own `msg.sender`, stealing the attestation.

**Mitigation**: D2 binding prevents this. The proof's public signal 0 is `bindingHash(msg.sender, challengeId)`, and the contract recomputes this from the actual `msg.sender`. A copy-paste attack would fail verification.

**Residual risk**: None for this specific scenario; this is the core benefit of D2.

### 8. Liveness griefing

**Risk**: A bonded validator stops responding, causing `finalize` to liveness-slash them repeatedly.

**Mitigation**: 1% slash per missed claim caps at ~MIN_STAKE after ~100 missed claims. Validators can proactively `requestUnbond` if they need to exit.

**Residual risk**: Minor — losing ~10 SKR per missed claim is within a reasonable operator SLA.

### 9. Decay bypass via resubmission

**Risk**: A claimant resubmits the same skill proof repeatedly to refresh the decay timestamp.

**Mitigation**: Each submission is a distinct record; the UI shows all records and the aggregate decayed score. The score function sums across all records regardless of age. Resubmission *does* effectively refresh, and in v0 this is **a feature** — skills must be periodically re-attested to remain fresh.

**Residual risk**: Resubmissions are gas-cheap and claimants can farm them. v1 may add a cooldown per (claimant, challenge) pair.

### 10. Slashing ambiguity: equivocation vs. correct minority

**Risk**: A committee member votes honestly NO but the majority incorrectly accepts. Their 5% slash is punishment for honesty.

**Mitigation**: v0 treats the majority outcome as ground truth. Validators who are confident the majority is wrong should not participate in that claim (liveness slash is 5x smaller than equivocation slash, so abstaining is the lesser evil).

**Residual risk**: This is a known game-theoretic weakness. v1 should add a challenge period where slashed minorities can dispute the outcome with an appeals committee.

## Disclosures

This threat model will be published alongside the v0 deployment. Any operator running `skr validate` must acknowledge it.
