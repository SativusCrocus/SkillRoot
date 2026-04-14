# Bootstrapping — 8 to 10 week solo timeline

Solo dev, MacBook + frontier AI. Target: end-to-end working system on Base Sepolia with 1 circuit, 5 committed external validators, and a public dApp.

## Week-by-week

### Week 1 — Environment + Contracts scaffolding
- [x] Install Foundry, Node 20, pnpm 9, Rust, Circom 2, snarkjs 0.7
- [x] `git init`, monorepo skeleton, workspaces, root `.gitignore`
- [x] `forge init` contracts/, install OZ v5.0.2 + forge-std
- [x] Write all 11 contract src files (SKRToken, StakingVault, ChallengeRegistry, Sortition, AttestationStore, AttestationEngine, QueryGateway, Governance, interfaces, MockVerifier, MathVerifierAdapter)
- [x] `forge build` green

### Week 2 — Tests (Gate 1)
- [x] 6 unit test files
- [x] E2E.t.sol using MockVerifier: bond → propose/activate → submit → draw → vote → finalize → query
- [x] AttestationEngineReal.t.sol placeholder (gated)
- [x] `forge test` all green → **Gate 1**

### Week 3 — Math circuit + trusted setup
- [x] `circuits/common/claimant_binding.circom` (pass-through)
- [x] `circuits/math/math.circom` — modexp, ~8.6k constraints
- [x] `circuits/math/build.sh` — compile → setup → contribute → export verifier
- [x] `circuits/scripts/` helpers (gen-input.ts, prove.ts)
- [x] Download `pot14_final.ptau`
- [x] Run build.sh → `MathVerifier.sol` emitted
- [x] Swap adapter into tests → **Gate 2**

### Week 4 — Frontend (Gate 3)
- [x] Next.js 14 `--app --src-dir --tailwind` with `output: 'export'`
- [x] `/`, `/submit`, `/me` pages
- [x] wagmi v2 + viem + RainbowKit providers
- [x] Read from QueryGateway, write submitClaim with uploaded calldata
- [x] `pnpm build` → static `out/` → **Gate 3**

### Week 5 — CLI (Gate 4)
- [x] `@skillroot/cli` package, tsup single-binary build
- [x] commands: challenges, solve, submit, query, stake, validate (folded daemon)
- [x] End-to-end against Anvil: stake → solve → submit → validate → query → **Gate 4**

### Week 6 — Scripts + docs + Base Sepolia deploy (Gate 5)
- [x] `scripts/anvil-e2e.sh` headless full lifecycle → **Gate 5** ✅
- [x] `scripts/deploy-sepolia.sh`, `scripts/seed-challenges.sh`
- [x] 7 markdown docs: architecture, contracts, circuits, tokenomics, bootstrapping, threat-model, ROADMAP
- [x] **(manual)** Deploy to Base Sepolia, write `deployments/base-sepolia.json`
      → deployed 2026-04-13 via `./scripts/deploy-sepolia.sh` — 10 contracts live
- [x] **(manual)** Seed math challenge via governance transaction
      → challenge #1 (APPLIED_MATH) ACTIVE via `./scripts/seed-challenges.sh`

### Week 7 — dApp hosting + external validator onboarding
- [x] **(manual)** Vercel production deployment
      → live at https://app-nine-rho-70.vercel.app — env vars set via `vercel env add`
- [x] Write validator operator guide → `docs/VALIDATOR-OPERATOR.md`
- [ ] **(manual)** Invite 5 external operators from target communities (ZK, math proofs, formal methods)
- [ ] **(manual exec, scripted)** Grant 5,000 SKR each from governance treasury (25k SKR operator grants)
      → run `OPERATORS=0x…,0x…,0x…,0x…,0x… ./scripts/grant-operators.sh`
      → validated end-to-end on anvil
- [ ] **(manual)** Assist with initial bonding txns
- [x] **(scripted)** Internal bootstrap smoke test — 5 dev-operated validators, first attestation finalized
      → `./scripts/bootstrap-first-attestation.sh` (fund → stake → run validate daemons → submit claim → vote → finalize)
      → `./scripts/bootstrap-verify.sh` (8 post-bootstrap checks, all green)
      → claim #1 `FINALIZED_ACCEPT` on 2026-04-14 in block 40207885; tx `0xb82542808aeadcd29b05a1f41c6a0148566c786dc392a874d666f91ed9acd7eb`
- [ ] **(manual)** Run first attested claim with real (non-solo) committee

### Week 8 — Hardening, feedback loop
- [ ] **(manual)** Monitor first 50 real claims
- [ ] **(manual, reactive)** Fix edge cases reported by operators
- [x] Publish ROADMAP → `docs/ROADMAP.md`
- [ ] **(manual exec, scripted)** Handoff: rotate genesis governance from deployer EOA to `Governance` contract + 5-signer multi-sig
      → run `./scripts/handoff-governance.sh` (defaults to Governance contract; pass `OWNER=<Safe>` for a direct multi-sig rotation)
      → validated end-to-end on anvil; writes a receipt JSON to `deployments/handoff-<timestamp>.json`

### Weeks 9–10 — buffer
Contingency for: circuit debugging, frontend bugs, validator onboarding friction, documentation gaps, additional circuit proposal from an external contributor.

## Governance bootstrap

At genesis:
1. Deployer holds 100M SKR and the genesis governance role of every subsystem contract.
2. Deployer transfers 100M → Governance contract immediately in `Deploy.s.sol`.
3. Deployer transfers the `governance` role of each subsystem (Token, Vault, Registry, Store, Engine) to the Governance contract.
4. Deployer can still interact with the system **only as a normal user** from this point.
5. During weeks 7–8, the Governance contract is itself controlled by a 5-signer multi-sig (Gnosis Safe) after validator onboarding.
6. By week 10, the multi-sig has demonstrated at least 1 live governance execution (adding the next challenge, for example).

## Exit criteria for v0

- 5 independent validators bonded and operating `skr validate`
- 50+ attestations finalized on Base Sepolia
- Math circuit proofs verify on-chain in <300k gas
- Public dApp live (v0 ships on Vercel at [`app-nine-rho-70.vercel.app`](https://app-nine-rho-70.vercel.app); IPFS/Fleek mirror is a v1 item)
- `ROADMAP.md` published with v1 scope
- Threat model disclosed publicly, with the single-party ceremony explicitly flagged
