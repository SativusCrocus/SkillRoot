# ForgeGuard — 8-Week Milestone Plan

Target: Solo MacBook + AI, starting from today's deliverable.

## Week 1 (Done): Foundation
- [x] Forge circuit (`circuits/forge/forge_challenge.circom`) — Poseidon commitment, D2 binding
- [x] `ForgeGuard.sol` — submit, break, finalize, patch, treasury
- [x] `ForgeVerifierAdapter.sol` — snarkjs bridge for forge circuit
- [x] `StakingVault` extension — `forgeGuard` address, `yieldBoostBps`, `addYieldBoost()`
- [x] `Deploy.s.sol` updated with ForgeGuard in deployment pipeline
- [x] 13 Foundry tests passing (full lifecycle, edge cases, regression)
- [x] `gen-forge-input.ts` witness generator

## Week 2: Circuit Build Pipeline
- [ ] Add `build-forge-circuit.sh` (compile, ptau, groth16 setup, export verifier)
- [ ] Generate `ForgeVerifier.sol` from snarkjs for the forge circuit
- [ ] Wire `ForgeVerifierAdapter` to the generated verifier
- [ ] End-to-end prove + verify test with real forge proof (not MockVerifier)
- [ ] Add forge circuit to `scripts/build-circuits.sh`

## Week 3: Mirage Isolation Layer
- [ ] Off-chain mirage runner: Node script that clones target circuit + staking state
- [ ] Mirage sandboxing: hash-pinned snapshot of circuit constraints + stake distribution
- [ ] On-chain `mirageHash` field in Forge struct (keccak of snapshot)
- [ ] Test: mirage hash matches expected snapshot for math circuit

## Week 4: Break Proof Strengthening
- [ ] Extend forge circuit to support exploit-type-specific constraint checks
  - Collision: prove two distinct witnesses that satisfy the same public signals
  - Range: prove a witness outside expected bounds that passes
  - Underconstraint: prove a non-semantic witness that satisfies all constraints
- [ ] Update `breakMirage` to validate exploit type matches break proof structure
- [ ] Fuzzing: Foundry fuzz tests for forge submission + break flows

## Week 5: Governance Integration
- [ ] Patch proposal → Governance proposal pipeline
  - `submitPatch` triggers a Governance.propose() with calldata for circuit upgrade
  - <24h vote window for security patches (separate from normal 5-day VOTING_PERIOD)
- [ ] Emergency governance path: if forge breaks critical circuit, auto-deprecate via ChallengeRegistry
- [ ] Tests: patch → governance vote → circuit upgrade flow

## Week 6: Economic Tuning + Yield Distribution
- [ ] Implement actual yield distribution in StakingVault (uses `yieldBoostBps`)
- [ ] Dynamic bounty sizing: scale `BOUNTY_AMOUNT` by target challenge `signalWeight`
- [ ] Dynamic bond sizing: scale `FORGE_BOND` by treasury capacity
- [ ] Slashing for frivolous forge spam (repeated failed submissions from same address)
- [ ] Economic model tests: simulate 100 forges, verify treasury sustainability

## Week 7: CLI + Frontend Integration
- [ ] `cli/` commands: `forge submit`, `forge break`, `forge status`, `forge fund`
- [ ] `app/` dashboard: active mirages, break window countdown, treasury balance
- [ ] QueryGateway extension: `forgeStats()` view for dApp integration
- [ ] Notification hooks: emit events that off-chain indexers can subscribe to

## Week 8: Testnet Deploy + Hardening
- [ ] Deploy ForgeGuard to Base Sepolia alongside existing contracts
- [ ] Run 3+ end-to-end forge challenges on testnet (submit, break, survive)
- [ ] Gas optimization pass on ForgeGuard (target <300k gas for submitForge)
- [ ] Security review: reentrancy, front-running, oracle manipulation vectors
- [ ] Documentation: update README, add ForgeGuard section to docs/
- [ ] Final integration test: `anvil-e2e.sh` includes forge lifecycle
