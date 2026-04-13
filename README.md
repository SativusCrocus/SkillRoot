<p align="center">
  <img src="app/public/logo.svg" alt="SkillRoot" width="120" height="120" />
</p>

<h1 align="center">SkillRoot</h1>

<p align="center">
  <strong>The Bitcoin-level primitive for human capability signaling.</strong>
</p>

<p align="center">
  <a href="https://app-nine-rho-70.vercel.app"><img src="https://img.shields.io/badge/testnet-live-22d3ee?style=flat-square" alt="Testnet Live" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-8b5cf6?style=flat-square" alt="MIT License" /></a>
  <img src="https://img.shields.io/badge/solidity-0.8.24-6366f1?style=flat-square" alt="Solidity 0.8.24" />
  <img src="https://img.shields.io/badge/circom-2-22d3ee?style=flat-square" alt="Circom 2" />
  <img src="https://img.shields.io/badge/chain-Base%20Sepolia-a78bfa?style=flat-square" alt="Base Sepolia" />
  <img src="https://img.shields.io/badge/three.js-r170-000000?style=flat-square&logo=threedotjs" alt="Three.js r170" />
</p>

<p align="center">
  Prove a skill with zero-knowledge proofs. A stake-weighted validator committee attests. The result is a permanent, decayed on-chain skill score readable by any dApp &mdash; no credentials, no gatekeepers, no universities.
</p>

---

## 3D Silk Frontend

> Glassmorphism interface with real-time 3D skill visualization. Three.js + React Three Fiber + Framer Motion on a void-black canvas with electric neon accents.

<p align="center">
  <!-- Screenshot placeholder — replace after first build: pnpm dev → browser screenshot -->
  <img src="docs/screenshots/hero.png" alt="SkillRoot — 3D Silk Hero" width="720" />
</p>

<table>
<tr>
<td width="50%">

<!-- Screenshot placeholder -->
<img src="docs/screenshots/submit.png" alt="Submit Proof" width="100%" />
<p align="center"><em>Submit attestation &mdash; glass form with drag-drop proof upload</em></p>

</td>
<td width="50%">

<!-- Screenshot placeholder -->
<img src="docs/screenshots/profile.png" alt="Skill Profile" width="100%" />
<p align="center"><em>Skill identity &mdash; 3D node graph with decayed score bars</em></p>

</td>
</tr>
</table>

- **3D Skill Graph** &mdash; floating domain nodes orbit a central protocol identity in a Three.js scene
- **Glassmorphism** &mdash; heavy frosted-glass surfaces with animated conic-gradient borders
- **Silk Palette** &mdash; void black `#030014` &rarr; electric cyan `#22d3ee` &rarr; violet `#8b5cf6`
- **Particle Systems** &mdash; ambient star-field particles with organic drift motion
- **60fps Motion** &mdash; Framer Motion staggered entrance choreography throughout

---

## How It Works

```
Claimant                  Protocol                    Readers
─────────                 ────────                    ───────
  │
  │  1. solve challenge    ┌──────────────────┐
  │  ──────────────────►   │ Groth16 ZK Proof │
  │                        └────────┬─────────┘
  │  2. submit on-chain             │
  │  ──────────────────►   ┌────────▼─────────┐
  │                        │ AttestationEngine │
  │                        │  verify proof     │
  │                        │  draw committee   │
  │                        └────────┬─────────┘
  │                                 │
  │                        ┌────────▼─────────┐
  │                        │  Validator Vote   │
  │                        │  (7-member jury)  │
  │                        └────────┬─────────┘
  │                                 │
  │                        ┌────────▼─────────┐
  │  3. skill recorded     │ AttestationStore  │──────►  dApps
  │  ◄──────────────────   │  decayed scores   │──────►  wallets
  │                        └──────────────────┘──────►  protocols
```

## Architecture

| Layer | Component | What It Does |
|-------|-----------|-------------|
| **Token** | `SKRToken.sol` | Fixed 100M ERC20Votes supply. No inflation. Slashing burns to `0xdead`. |
| **Staking** | `StakingVault.sol` | Bond/unbond/slash. 1000 SKR minimum. 14-day unbond delay. Dense validator array for sortition. |
| **Challenges** | `ChallengeRegistry.sol` | Propose/activate/deprecate skill challenges. 10k SKR proposer bond. |
| **Selection** | `Sortition.sol` | Stake-weighted 7-member committee draw. `blockhash(n+4)` entropy. 240-block reveal window. |
| **Engine** | `AttestationEngine.sol` | Orchestrator: verify proof, draw committee, collect votes, finalize. D2 on-chain binding. |
| **Storage** | `AttestationStore.sol` | Permanent attestation records with time-decayed score computation. |
| **Gateway** | `QueryGateway.sol` | Single `verify(address)` returns `uint256[4]` domain scores for any reader. |
| **Governance** | `Governance.sol` | On-chain proposal/vote/execute. Governs challenge activation, parameter changes, treasury. |
| **Security** | `ForgeGuard.sol` | Permissionless forge challenges + mirage break/survive lifecycle. |
| **ZK Circuit** | `math.circom` | Groth16 modular exponentiation circuit. Proves knowledge of `(base, exp)` satisfying `base^exp mod N = result`. |
| **Frontend** | Next.js 14 + Three.js | 3D silk glassmorphism dApp. Three.js skill graph, glass panels, particle systems. Static export. |
| **CLI** | `skr` | TypeScript CLI: `solve` (generate proof), `validate` (run validator daemon), `status` (check scores). |

## Monorepo Layout

```
contracts/    Foundry / Solidity 0.8.24 smart contracts
circuits/     Circom 2 + snarkjs Groth16 circuits
app/          Next.js 14 + Three.js + R3F — 3D silk glassmorphism frontend (static export)
cli/          TypeScript CLI (skr) with integrated validator daemon
docs/         Architecture, contracts, circuits, tokenomics, threat model, roadmap
scripts/      Automation (setup, build, ceremony, deploy, e2e)
```

## Base Sepolia Deployment

All contracts are live on **Base Sepolia** (chain 84532). Frontend: [app-nine-rho-70.vercel.app](https://app-nine-rho-70.vercel.app)

| Contract | Address |
|----------|---------|
| SKRToken | [`0xbd8Fe0fE752A1B0135DDdD99357De060e2C92392`](https://sepolia.basescan.org/address/0xbd8Fe0fE752A1B0135DDdD99357De060e2C92392) |
| Governance | [`0x0Bd5D8Cb003EE175D19B29F8B50E99d5959eABDE`](https://sepolia.basescan.org/address/0x0Bd5D8Cb003EE175D19B29F8B50E99d5959eABDE) |
| StakingVault | [`0x0aD5A748965895709a0D68E3e669dCB97a6B43C1`](https://sepolia.basescan.org/address/0x0aD5A748965895709a0D68E3e669dCB97a6B43C1) |
| ChallengeRegistry | [`0x7585959e8f0B5C17D40ff0Cd2564417E50135c78`](https://sepolia.basescan.org/address/0x7585959e8f0B5C17D40ff0Cd2564417E50135c78) |
| Sortition | [`0x7022D0326E296F78664F4506e42D39aD0bd188D6`](https://sepolia.basescan.org/address/0x7022D0326E296F78664F4506e42D39aD0bd188D6) |
| AttestationStore | [`0x013D4edC39B9b594dD809139b283Eb6ef313c8AA`](https://sepolia.basescan.org/address/0x013D4edC39B9b594dD809139b283Eb6ef313c8AA) |
| AttestationEngine | [`0x86b5A121568829981593e5Be2D597dFb99DC7E49`](https://sepolia.basescan.org/address/0x86b5A121568829981593e5Be2D597dFb99DC7E49) |
| QueryGateway | [`0xFb648E415BAbBbFBf882Cc64a02cBc5DAFAB0D14`](https://sepolia.basescan.org/address/0xFb648E415BAbBbFBf882Cc64a02cBc5DAFAB0D14) |
| MathGroth16Verifier | [`0x39041f0DB8E566c72D407d81F67B931560B30619`](https://sepolia.basescan.org/address/0x39041f0DB8E566c72D407d81F67B931560B30619) |
| MathVerifierAdapter | [`0x0984eC92acf7AA83454c26862ef25856Df862Edd`](https://sepolia.basescan.org/address/0x0984eC92acf7AA83454c26862ef25856Df862Edd) |

Challenge #1 (APPLIED_MATH &mdash; modular exponentiation) is **ACTIVE**. See [`docs/TESTNET_FIRST_ATTESTATION.md`](docs/TESTNET_FIRST_ATTESTATION.md) for the end-to-end walkthrough.

## Quickstart

```bash
# 1. Clone and install
git clone https://github.com/SativusCrocus/SkillRoot.git
cd SkillRoot
./scripts/setup.sh          # idempotent toolchain install (foundry, circom, snarkjs, node)
pnpm install                # workspace dependencies (includes three.js / R3F)

# 2. Build everything
forge build --root contracts
./scripts/build-circuits.sh  # math circuit → MathVerifier.sol

# 3. Test
forge test --root contracts -vvv

# 4. Run the full lifecycle on local testnet
./scripts/anvil-e2e.sh

# 5. Start the 3D frontend
pnpm dev                    # → http://localhost:3000
```

## Skill Domains

v0 ships one active circuit. The contract layer supports four domain slots:

| Domain | Circuit | Statement | Status |
|--------|---------|-----------|--------|
| `APPLIED_MATH` | `math.circom` | Modular exponentiation: prove `base^exp mod N = result` | **Active** |
| `ALGO` | &mdash; | Algorithm correctness under constraint budget | v1 |
| `FORMAL_VER` | &mdash; | SAT instance satisfies committed CNF formula | v1 |
| `SEC_CODE` | &mdash; | Vulnerability pattern detection in committed bytecode | v1 |

## Tokenomics

| Parameter | Value |
|-----------|-------|
| Total supply | 100,000,000 SKR (fixed, deflationary) |
| Minimum stake | 1,000 SKR |
| Unbond delay | 14 days |
| Committee size | 7 validators |
| Liveness slash | 1% of stake |
| Equivocation slash | 5% of stake |
| Proposer bond | 10,000 SKR |

100% of genesis supply goes to the `Governance` contract. No investor round, no team vesting, no airdrop. Early validators earn stake through governance-approved operator grants.

## Design Invariants

- Exactly one ZK circuit in v0 &mdash; modular exponentiation
- Fixed 100M SKR supply, no inflation
- Contract-side claimant binding: `keccak256(abi.encode(msg.sender, challengeId))`
- Next.js static export only (IPFS-compatible)
- Validator daemon folded into `skr validate` &mdash; no separate daemon package
- All slashed tokens burned (deflationary under adversarial behavior)

## Frontend Stack

| Package | Version | Role |
|---------|---------|------|
| Next.js | 14.2.15 | Static-export framework (`output: 'export'`) |
| Three.js | 0.170.0 | WebGL 3D rendering engine |
| React Three Fiber | 8.17.10 | Declarative Three.js for React |
| Drei | 9.117.0 | R3F helpers (Float, MeshDistortMaterial, environment) |
| Framer Motion | 11.11.11 | Layout animations, entrance choreography |
| Tailwind CSS | 3.4.x | Utility-first CSS with custom silk design tokens |
| wagmi + viem | 2.x | Ethereum wallet connection and contract reads |
| RainbowKit | 2.1.x | Wallet connect modal (themed to silk palette) |

## Documentation

| Document | Contents |
|----------|----------|
| [`docs/architecture.md`](docs/architecture.md) | System topology, component roles, data flow |
| [`docs/contracts.md`](docs/contracts.md) | Contract API reference, storage layout, access control |
| [`docs/circuits.md`](docs/circuits.md) | Circuit constraints, trusted setup, verification |
| [`docs/tokenomics.md`](docs/tokenomics.md) | Supply, staking, slashing, distribution |
| [`docs/threat-model.md`](docs/threat-model.md) | Attack surface analysis, risk registry |
| [`docs/bootstrapping.md`](docs/bootstrapping.md) | 8-week launch plan, operator onboarding |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | v1 scope, P0/P1 priorities, research track |
| [`docs/VALIDATOR-OPERATOR.md`](docs/VALIDATOR-OPERATOR.md) | Validator setup and operations guide |

## Security

**v0 is testnet-only and unaudited.** Do not use with real value.

Known limitations documented in [`docs/threat-model.md`](docs/threat-model.md):
- Single-party phase 2 trusted setup (v1 requires multi-party ceremony)
- `blockhash` entropy vulnerable to sequencer grinding (v1 switches to VRF)
- No timelock on governance execution (v1 adds TimelockController)

## Contributing

This project is in active development. See [`docs/ROADMAP.md`](docs/ROADMAP.md) for planned work. Issues will be created after the v0 testnet phase has run for 30+ days.

## License

[MIT](LICENSE) &copy; 2026 SkillRoot contributors
