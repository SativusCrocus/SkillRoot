# Bootstrapping — v0 timeline

Solo dev, MacBook + frontier AI. Target: end-to-end working system on Base Sepolia with 1 claim circuit, 1 paired fraud circuit, the 24h fraud-proof window replacing any committee, and a public dApp.

## Week-by-week

### Week 1 — Environment + Contracts scaffolding
- [x] Install Foundry, Node 20, pnpm 9, Rust, Circom 2, snarkjs 0.7
- [x] `git init`, monorepo skeleton, workspaces, root `.gitignore`
- [x] `forge init` contracts/, install OZ v5.0.2 + forge-std
- [x] Write core contract src files (SKRToken, StakingVault, ChallengeRegistry, AttestationStore, AttestationEngine, QueryGateway, interfaces, MockVerifier, verifier adapters)
- [x] `forge build` green

### Week 2 — Tests (Gate 1)
- [x] Unit test files for token, vault, registry, store, engine
- [x] E2E.t.sol using MockVerifier: bond → propose/activate → submit → fraud-prove or finalize → query
- [x] AttestationEngineReal.t.sol against real Groth16 verifier
- [x] `forge test` all green → **Gate 1**

### Week 3 — Math circuit + trusted setup
- [x] `circuits/common/claimant_binding.circom` (pass-through)
- [x] `circuits/math/math.circom` — modexp, ~8.6k constraints
- [x] `circuits/math/build.sh` — compile → setup → contribute → export verifier
- [x] Download `pot14_final.ptau`
- [x] Run build.sh → `MathGroth16Verifier.sol` emitted
- [x] Swap adapter into tests → **Gate 2**

### Week 4 — Fraud circuit + v0.2.0-no-vote architecture pivot
- [x] Design dual fraud circuit: proves a pending claim's public signals are inconsistent with the challenge statement
- [x] Drop `Governance.sol`, `Sortition.sol`, `ForgeGuard.sol` from the contract set
- [x] Rework `AttestationEngine.sol`: `submitClaim` → 24h fraud window → `submitFraudProof` / `finalizeClaim`
- [x] `ChallengeRegistry.sol`: bonded proposal + permissionless rejection/activation (no governance vote)

### Week 5 — Frontend (Gate 3)
- [x] Next.js 14 `--app --src-dir --tailwind` with `output: 'export'`
- [x] `/`, `/submit`, `/me` pages wired to the 8-contract v0.2.0-no-vote set
- [x] wagmi v2 + viem + RainbowKit providers
- [x] Read from QueryGateway, write submitClaim with uploaded calldata
- [x] `pnpm build` → static `out/` → **Gate 3**

### Week 6 — CLI (Gate 4)
- [x] `@skillroot/cli` package, tsup single-binary build
- [x] commands: `challenges`, `solve`, `submit`, `dispute`, `query`, `stake`
- [x] End-to-end against Anvil: stake → solve → submit → (optionally dispute) → finalize → query → **Gate 4**

### Week 7 — Scripts + docs + Base Sepolia deploy (Gate 5)
- [x] `scripts/anvil-e2e.sh` headless full lifecycle → **Gate 5** ✅
- [x] `scripts/deploy-sepolia-novote.sh`, `scripts/testnet-verify-novote.sh`
- [x] Markdown docs: architecture, contracts, circuits, tokenomics, bootstrapping, threat-model, ROADMAP
- [x] **(manual)** Deploy to Base Sepolia under v0.2.0-no-vote, write `deployments/base-sepolia.json`
      → 8 canonical contracts live, deployer key burned after activation
- [x] **(manual)** Seed math challenge → challenge #1 (APPLIED_MATH) ACTIVE

### Week 8 — dApp hosting + first attestation
- [x] **(manual)** Vercel production deployment → live at https://app-nine-rho-70.vercel.app
- [x] **(live)** First attestation under v0.2.0-no-vote
      → claim #1 submitted at block 40292380; tx `0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9`
      → 24h fraud-proof window closed with no challenge
      → `FINALIZED_ACCEPT`

### Week 9+ — Hardening, feedback loop
- [ ] **(manual)** Monitor first 50 real claims on mainnet Base Sepolia
- [ ] **(manual, reactive)** Fix edge cases reported by operators
- [x] Publish ROADMAP → `docs/ROADMAP.md`
- [ ] Reference fraud-watcher daemon + documented SLA

## Exit criteria for v0.2.0-no-vote

- Fraud-proof flow verified live on Base Sepolia
- 50+ attestations finalized
- Math + fraud circuit proofs verify on-chain within expected gas envelope
- Public dApp live (v0 ships on Vercel at [`app-nine-rho-70.vercel.app`](https://app-nine-rho-70.vercel.app); IPFS/Fleek mirror is a v1 item)
- `ROADMAP.md` published with v1 scope
- Threat model disclosed publicly, with the single-party ceremony explicitly flagged
