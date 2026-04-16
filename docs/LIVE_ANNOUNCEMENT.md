# SkillRoot v0.2.0-no-vote — Public Announcement (copy-paste ready)

All links, addresses, and numbers below are live.

---

## X / Twitter Thread

Post each block as a separate reply in the thread.

---

**1/6**

SkillRoot v0.2.0-no-vote is live on Base Sepolia.

First on-chain attestation finalized under the new fraud-proof flow. No committee. No vote. Just a ZK proof, a 100 SKR bond, and a 24-hour window.

https://app-nine-rho-70.vercel.app

---

**2/6**

What happened:

A claimant generated a Groth16 ZK proof for a modular exponentiation challenge (3^7 mod 13).

The proof was verified on-chain by a Solidity verifier. 100 SKR was locked as a claim bond. A 24-hour fraud window opened. No staker submitted a valid fraud proof. The attestation auto-finalized.

---

**3/6**

The primitive:

- Submit a ZK proof for a domain-specific challenge, post a 100 SKR bond
- On-chain verifier checks the proof cryptographically
- 24h fraud-proof window: any staker with ≥ 1,000 SKR can refute with a valid fraud proof (→ 50 SKR reward, 50 SKR burned)
- If the window closes with no successful fraud proof, the claim is accepted and the bond returned

No committee. No vote. No governance.

---

**4/6**

What's on-chain right now (Base Sepolia):

- 8 canonical contracts deployed
- 1 active challenge (APPLIED_MATH)
- First fraud-proof-flow attestation finalized
- Scores queryable via QueryGateway

Engine: https://sepolia.basescan.org/address/0xF2541F68f47f5aB978979B5Ab766f08750d915e8

---

**5/6**

Skill scores decay over time:

- Algorithmic: 2-year half-life
- Formal verification: 3-year half-life
- Applied math: 3-year half-life
- Security / code: 1-year half-life

Your score isn't a badge. It's a signal that degrades unless you keep proving.

---

**6/6**

Fraud-provers wanted. 1,000 SKR stake. Watch claims, submit a fraud proof if you see an invalid one, earn 50 SKR per win.

Guide: https://github.com/SativusCrocus/SkillRoot/blob/main/docs/VALIDATOR_ONBOARDING.md

App: https://app-nine-rho-70.vercel.app

---

## Discord / Farcaster Announcement

**SkillRoot v0.2.0-no-vote — Live on Base Sepolia**

The first on-chain skill attestation under the fraud-proof flow has been finalized.

**What shipped:**
- 8 canonical smart contracts on Base Sepolia (chain 84532)
- Groth16 ZK proof verification for modular exponentiation
- 24-hour fraud-proof window replacing the validator committee
- Paired fraud circuit + adapter for permissionless refutation
- Time-decayed attestation scores (queryable via CLI and frontend)
- 3D glassmorphism frontend on Vercel

**Links:**
- App: https://app-nine-rho-70.vercel.app
- AttestationEngine: https://sepolia.basescan.org/address/0xF2541F68f47f5aB978979B5Ab766f08750d915e8
- First attestation tx: https://sepolia.basescan.org/tx/0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9
- Repo: https://github.com/SativusCrocus/SkillRoot

**Want to run a fraud-prover?**
Follow the onboarding guide: https://github.com/SativusCrocus/SkillRoot/blob/main/docs/VALIDATOR_ONBOARDING.md

Requirements: 1,000 SKR stake, Node 20+, Foundry.

---

## GitHub Release

**Tag:** `v0.2.0-no-vote`
**Title:** `v0.2.0 — Fraud-Proof Flow Live on Base Sepolia`

---

**Body:**

## SkillRoot v0.2.0-no-vote

Dropped the validator committee. Replaced the 24h voting window with a 24h fraud-proof window. Shrank the contract set from 10 to 8.

### Deployed Contracts (Base Sepolia, chain 84532)

| Contract | Address |
|----------|---------|
| SKRToken              | [`0xebEB1dAC3F774b47e28844D1493758838D8463B2`](https://sepolia.basescan.org/address/0xebEB1dAC3F774b47e28844D1493758838D8463B2) |
| StakingVault          | [`0x8CCdc62e5762f89d0D17fc5e55Ae3555c207Ad6b`](https://sepolia.basescan.org/address/0x8CCdc62e5762f89d0D17fc5e55Ae3555c207Ad6b) |
| AttestationStore      | [`0x3b6a969DCAD3d79164dA2AD75c2191350BF536a8`](https://sepolia.basescan.org/address/0x3b6a969DCAD3d79164dA2AD75c2191350BF536a8) |
| ChallengeRegistry     | [`0xbD13B7822bBc4cC6C0C53CA08497643C6085294B`](https://sepolia.basescan.org/address/0xbD13B7822bBc4cC6C0C53CA08497643C6085294B) |
| AttestationEngine     | [`0xF2541F68f47f5aB978979B5Ab766f08750d915e8`](https://sepolia.basescan.org/address/0xF2541F68f47f5aB978979B5Ab766f08750d915e8) |
| QueryGateway          | [`0xe4A4c37B59F29807840b1DB22C45C66dcB5D01A2`](https://sepolia.basescan.org/address/0xe4A4c37B59F29807840b1DB22C45C66dcB5D01A2) |
| MathGroth16Verifier   | [`0x8176831054075DaF6B26783491a04D3C14eFD41b`](https://sepolia.basescan.org/address/0x8176831054075DaF6B26783491a04D3C14eFD41b) |
| MathVerifierAdapter   | [`0xde605f7BA61030916136f079731260B76bE8074C`](https://sepolia.basescan.org/address/0xde605f7BA61030916136f079731260B76bE8074C) |
| FraudGroth16Verifier  | [`0x1E39641eaf3930d19F8619184aE10b4f38a5a5bB`](https://sepolia.basescan.org/address/0x1E39641eaf3930d19F8619184aE10b4f38a5a5bB) |
| FraudVerifierAdapter  | [`0x173241d25feb42EA8D9D3D4c767788c6F23C62A7`](https://sepolia.basescan.org/address/0x173241d25feb42EA8D9D3D4c767788c6F23C62A7) |

### What's in this release

- **ZK attestation pipeline** — Circom 2 claim circuit + paired fraud circuit for modular exponentiation
- **Fraud-proof flow** — 24h window, permissionless challenge by any ≥ 1,000 SKR staker, 50/50 bond split on successful refutation
- **Auto-finalize** — any caller can finalize an unchallenged claim after the window; bond returns to claimant
- **Time-decayed scores** — domain-specific half-lives (1–3 years), queryable via `QueryGateway.verify()`
- **CLI** — `skr solve`, `skr submit`, `skr dispute`, `skr stake`, `skr query`, `skr challenges`
- **Frontend** — 3D silk glassmorphism UI (Three.js + R3F), wallet connect via RainbowKit, live at https://app-nine-rho-70.vercel.app
- **Tokenomics** — 100M fixed supply SKR, deflationary via claim-bond burns on successful fraud proofs

### First attestation (v0.2.0-no-vote)

- **Challenge:** APPLIED_MATH #1 (modular exponentiation)
- **Proof:** `3^7 mod 13 = 3` (Groth16, BN254)
- **Flow:** submitClaim (100 SKR bond) → 24h window → finalizeClaim
- **Result:** FINALIZED_ACCEPT
- **Tx:** [`0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9`](https://sepolia.basescan.org/tx/0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9)

### Run it yourself

```bash
git clone https://github.com/SativusCrocus/SkillRoot.git
cd SkillRoot
pnpm install
./scripts/setup.sh           # install toolchain
./scripts/build-circuits.sh  # compile circuits
```

### Known limitations (v0)

- Single-party trusted setup (v1 requires multi-party ceremony for both claim and fraud circuits)
- 1 claim-circuit domain active (3 more in v1, each with a paired fraud circuit)
- Fraud-watcher liveness: relies on at least one bonded staker monitoring claims

---

## Release Commands

```bash
git tag -a v0.2.0-no-vote -m "v0.2.0 — Fraud-Proof Flow Live on Base Sepolia"
git push origin v0.2.0-no-vote

gh release create v0.2.0-no-vote \
  --title "v0.2.0 — Fraud-Proof Flow Live on Base Sepolia" \
  --notes-file docs/LIVE_ANNOUNCEMENT.md \
  --prerelease
```
