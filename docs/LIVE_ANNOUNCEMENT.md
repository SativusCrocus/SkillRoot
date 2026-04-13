# SkillRoot v0 — Public Announcement (copy-paste ready)

All links, addresses, and numbers below are live. Replace `<CLAIM_TX>` with the actual finalization tx hash from the bootstrap script output.

---

## X / Twitter Thread

Post each block as a separate reply in the thread.

---

**1/7**

SkillRoot v0 is live on Base Sepolia.

First on-chain attestation finalized.

Zero-knowledge proof of skill. Validator consensus. Time-decayed scores. No resumes.

https://app-nine-rho-70.vercel.app

---

**2/7**

What happened:

A claimant generated a Groth16 ZK proof for a modular exponentiation challenge (3^7 mod 13).

The proof was verified on-chain. A 7-member committee was drawn via stake-weighted sortition. Validators voted. Consensus reached. Attestation recorded permanently.

---

**3/7**

The primitive:

- Submit a ZK proof that you solved a domain-specific challenge
- On-chain verifier checks it cryptographically
- Sortition draws a validator committee from staked participants
- Committee votes (66.66% quorum)
- Accepted attestations are stored with time-decaying scores

---

**4/7**

What's on-chain right now (Base Sepolia):

- 9 contracts deployed
- 5 validators bonded (5,000 SKR each)
- 1 active challenge (APPLIED_MATH)
- 1 finalized attestation
- Scores queryable via QueryGateway

Engine: https://sepolia.basescan.org/address/0x86b5A121568829981593e5Be2D597dFb99DC7E49

---

**5/7**

Skill scores decay over time:

- Algorithmic: 2-year half-life
- Formal verification: 3-year half-life
- Applied math: 3-year half-life
- Security/code: 1-year half-life

Your score isn't a badge. It's a signal that degrades unless you keep proving.

---

**6/7**

What's next:

- 3 new challenge domains (algo, formal verification, secure code)
- VRF-based sortition (replacing blockhash entropy)
- Governance timelock
- Multi-party trusted setup ceremony
- Mainnet

Roadmap: https://github.com/SativusCrocus/SkillRoot

---

**7/7**

Validators needed. 5,000 SKR stake. Run a daemon. Earn yield. Get slashed if you sleep.

Validator guide: https://github.com/SativusCrocus/SkillRoot/blob/main/docs/VALIDATOR_ONBOARDING.md

App: https://app-nine-rho-70.vercel.app

---

## Discord Announcement

Post in `#announcements`:

---

**SkillRoot v0 — Live on Base Sepolia**

The first on-chain skill attestation has been finalized.

**What shipped:**
- 9 smart contracts on Base Sepolia (chain 84532)
- Groth16 ZK proof verification for modular exponentiation
- Stake-weighted sortition committee (7 members per claim)
- 5 bonded validators, first committee drawn and voted
- Time-decayed attestation scores (queryable via CLI and frontend)
- 3D glassmorphism frontend on Vercel

**Links:**
- App: https://app-nine-rho-70.vercel.app
- AttestationEngine: https://sepolia.basescan.org/address/0x86b5A121568829981593e5Be2D597dFb99DC7E49
- First attestation tx: https://sepolia.basescan.org/tx/<CLAIM_TX>
- Repo: https://github.com/SativusCrocus/SkillRoot

**Want to validate?**
Follow the onboarding guide: https://github.com/SativusCrocus/SkillRoot/blob/main/docs/VALIDATOR_ONBOARDING.md

Requirements: 5,000 SKR stake, Node 20+, Foundry. Send your address in `#validators` to get funded.

---

## GitHub Release

**Tag:** `v0.1.0-testnet`
**Title:** `v0.1.0 — First Live Attestation on Base Sepolia`

---

**Body:**

## SkillRoot v0.1.0 — First Live Attestation

The SkillRoot primitive is live on Base Sepolia with its first finalized on-chain attestation.

### Deployed Contracts (Base Sepolia, chain 84532)

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

### What's in this release

- **ZK attestation pipeline** — Circom 2 circuit for modular exponentiation, Groth16 proofs verified on-chain via snarkjs-generated verifier
- **Validator consensus** — stake-weighted sortition draws 7-member committees, 66.66% quorum, liveness + equivocation slashing
- **Time-decayed scores** — domain-specific half-lives (1-3 years), queryable via `QueryGateway.verify()`
- **CLI** — `skr solve`, `skr submit`, `skr stake`, `skr validate` (daemon), `skr query`, `skr challenges`
- **Frontend** — 3D silk glassmorphism UI (Three.js + R3F), wallet connect via RainbowKit, live at https://app-nine-rho-70.vercel.app
- **ForgeGuard** — permissionless security challenge layer with mirage lifecycle
- **Tokenomics** — 100M fixed supply SKR (ERC20Votes), deflationary via slash burns

### First attestation

- **Challenge:** APPLIED_MATH #1 (modular exponentiation)
- **Proof:** `3^7 mod 13 = 3` (Groth16, BN254)
- **Validators:** 5 bonded, committee of 7 drawn via Sortition
- **Result:** FINALIZED_ACCEPT
- **Tx:** [`<CLAIM_TX>`](https://sepolia.basescan.org/tx/<CLAIM_TX>)

### Run it yourself

```bash
git clone https://github.com/SativusCrocus/SkillRoot.git
cd SkillRoot
pnpm install
./scripts/setup.sh           # install toolchain
./scripts/build-circuits.sh  # compile circuits
pnpm run e2e                 # full local flow on anvil
```

### Validate

See [VALIDATOR_ONBOARDING.md](docs/VALIDATOR_ONBOARDING.md) for the 5-step guide.

### Known limitations (v0)

- Blockhash entropy for sortition (v1 switches to VRF)
- No governance timelock (v1)
- Single-party trusted setup (v1 requires multi-party ceremony)
- 1 challenge domain active (3 more in v1)

---

## Release Commands

```bash
# Tag and push
git tag -a v0.1.0-testnet -m "v0.1.0 — First Live Attestation on Base Sepolia"
git push origin v0.1.0-testnet

# Create GitHub release (requires gh CLI)
gh release create v0.1.0-testnet \
  --title "v0.1.0 — First Live Attestation on Base Sepolia" \
  --notes-file docs/LIVE_ANNOUNCEMENT.md \
  --prerelease
```
