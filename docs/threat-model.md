# Threat Model — SkillRoot v0.2.0-no-vote

**Scope**: testnet only (Base Sepolia). This document enumerates known risks and explicitly does *not* claim production readiness.

## Disclaimer

SkillRoot v0.2.0-no-vote is an unaudited prototype. Do **not** use real assets or rely on SkillRoot attestations for any high-stakes decision. The trusted setup ceremony is single-party.

## Attack surface

### 1. Invalid claim submission

**Risk**: A claimant submits a claim whose ZK proof does not satisfy the underlying statement.

**Mitigation**: `submitClaim` calls `IZKVerifier.verifyProof` on-chain and reverts on failure. The claim never enters the PENDING queue.

**Residual risk**: Relies on the soundness of Groth16 + BN254. If either is broken, forged proofs pass verification — unchanged from any Groth16 deployment.

### 2. Sybil attacks on the fraud-prover set

**Risk**: Attacker creates many low-stake addresses to observe pending claims but cannot afford the 1,000 SKR minimum stake.

**Mitigation**: `FRAUD_PROVER_MIN_STAKE = 1_000 SKR` is checked inside `submitFraudProof`. Sub-threshold addresses cannot grief by spamming invalid fraud proofs — they are rejected at the stake check before any verifier call.

**Residual risk**: An attacker who bonds ≥ 1,000 SKR can spam invalid fraud proofs (each reverts); this only costs them gas. The engine is not economically impacted.

### 3. Fraud-prover liveness failure

**Risk**: No staker monitors the mempool, and a bogus claim auto-finalizes after 24h because nobody submitted a fraud proof.

**Mitigation**: Any bonded staker may submit a fraud proof at any point in the 24h window. 50 SKR reward per valid fraud proof plus burn of 50 SKR provides direct economic incentive to monitor.

**Residual risk**: In the bootstrap phase the staker set is small and may be offline. The mitigation is operational: multiple independent stakers run fraud-watcher daemons. Deferred: move to a SNARK-of-SNARK correctness proof that does not require liveness.

### 4. Single-party trusted setup

**Risk**: Whoever ran phase 2 could retain toxic waste and forge proofs.

**Mitigation**: Phase 1 uses Hermez's publicly audited Powers of Tau ceremony. Phase 2 entropy is documented and the contribution hash is published in `build/verification_key.json`.

**Residual risk**: Phase 2 is single-party. Before any mainnet deployment, a multi-party phase 2 ceremony with ≥3 independent contributors must be run and the verifier redeployed.

### 5. D2 binding revision

**Risk**: The claimant binding lives at the contract layer (`keccak256(abi.encode(msg.sender, challengeId)) & MASK248`), not inside the ZK circuit. A malicious AttestationEngine upgrade could weaken it.

**Mitigation**:
- AttestationEngine is non-upgradeable in v0 — no admin, no proxy.
- Binding formula is applied to both claim proofs (bound to `msg.sender`) and fraud proofs (bound to the **claim's** claimant+challengeId), preserving soundness for both directions.
- 248-bit mask still provides 248 bits of collision resistance.

**Residual risk**: Future upgradeability, if introduced, must be audited for binding preservation.

### 6. Front-running submitClaim

**Risk**: A mempool observer copies a pending claim's proof and submits it with their own `msg.sender`, stealing the attestation.

**Mitigation**: D2 binding prevents this. The proof's public signal 0 is `bindingHash(msg.sender, challengeId)`, and the contract recomputes this from the actual `msg.sender`. A copy-paste attack fails verification.

**Residual risk**: None for this specific scenario; this is the core benefit of D2.

### 7. Claim-bond griefing

**Risk**: A claimant ties up 100 SKR per submission and floods the engine with claims to inflate storage.

**Mitigation**: The bond cost (100 SKR × 24h lock-up) makes high-volume spam expensive; only valid claims are storage-accruing (invalid ones revert at `submitClaim` without state change).

**Residual risk**: Low. Spam storage cost is bounded by the bond × rate limit imposed by block gas.

### 8. Decay bypass via resubmission

**Risk**: A claimant resubmits the same skill proof repeatedly to refresh the decay timestamp.

**Mitigation**: Each submission is a distinct record; the UI shows all records and the aggregate decayed score. Resubmission *does* effectively refresh, and in v0 this is **a feature** — skills must be periodically re-attested to remain fresh.

**Residual risk**: Resubmissions cost the full 100 SKR bond lock-up plus 24h wait, so farming is already gas-ceiling bounded.

### 9. Fraud-circuit soundness

**Risk**: The fraud circuit accepts a proof that does not actually demonstrate the claim statement is false.

**Mitigation**: The fraud circuit is the dual of the claim circuit and uses the same Groth16 setup. Fraud proofs are bound via D2 to the exact (claimant, challengeId) they refute, preventing proof replay across claims.

**Residual risk**: A bug in the fraud circuit could allow accepting bogus fraud proofs → slashing an honest claimant. The fraud circuit must be audited alongside every new domain circuit before activation.

## Disclosures

This threat model is published alongside the v0.2.0-no-vote deployment. Any operator running a fraud-watcher on the testnet should read it.
