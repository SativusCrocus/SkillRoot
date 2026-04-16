# Tokenomics — SKR (v0.2.0-no-vote)

## Supply

**Fixed 100,000,000 SKR, minted once at genesis.** No `mint()` exists. Supply only decreases (via bond-slash burns to 0xdead).

```
INITIAL_SUPPLY = 100_000_000 ether   // 18 decimals
```

## Distribution (v0 genesis)

v0 has no investor round, no team vesting, no airdrop. The deployer key was burned after activating Challenge #1; there is no governance treasury pathway in this release. Early operators hold SKR through the initial distribution only.

## Staking

```
MIN_STAKE    = 1_000 SKR
UNBOND_DELAY = 14 days
```

In v0.2.0-no-vote staking serves one purpose: gating who may submit a fraud proof. Anyone with ≥ 1,000 SKR bonded in the vault is eligible to contest any pending claim inside its 24h window.

## Claim bond

```
CLAIM_BOND       = 100 SKR      // posted at submitClaim
CHALLENGE_WINDOW = 24 hours
```

Every claim locks 100 SKR for 24 hours. Two outcomes:

1. **No valid fraud proof** → bond returned in full at `finalizeClaim`. Attestation recorded.
2. **Valid fraud proof inside the window** → 50 SKR to prover, 50 SKR burned to `0xdead`. Claim rejected.

The claim bond is the only economic instrument. There is no liveness slash, no equivocation slash, no committee to discipline.

## Challenge proposal bond

```
PROPOSER_BOND = 10_000 SKR
```

Anyone can propose a new challenge by posting the bond. After a short inactivity window anyone may permissionlessly `activate` (bond refunded) or `reject` (bond burned). This keeps proposal spam costly without requiring governance.

## Game theory

### Claimant incentives

A claimant posts 100 SKR to submit. They get it back **only if** no fraud proof lands. If they submit a valid proof, the cryptography guarantees no fraud proof can succeed — any malicious fraud-prover attempt will itself fail `IZKVerifier.verifyProof`.

Dominant strategy: only submit when the underlying proof is sound.

### Fraud-prover incentives

A staker observing a bogus pending claim can earn 50 SKR by posting a valid fraud proof. Fraud proofs are permissionless among stakers ≥ 1,000 SKR; the first valid one wins the entire reward.

Dominant strategy: watch the mempool for invalid claims, run the fraud prover off-chain, submit when profitable.

### Attacker model

For an attacker to force acceptance of a bogus claim, they must submit a claim whose proof verifies under the on-chain Groth16 verifier **and** survive 24 hours without any other staker producing a valid fraud proof. The first condition requires breaking Groth16 soundness (≡ breaking BN254 discrete log). The second is a liveness assumption, bounded by `FRAUD_PROVER_MIN_STAKE` (currently 1000 SKR).

## Decay

Attestations decay over time per domain:

| Domain | Half-life |
|--------|-----------|
| APPLIED_MATH | 1095 days (3 years) |
| FORMAL_VER | 1095 days |
| ALGO | 730 days (2 years) |
| SEC_CODE | 365 days (1 year) |

Rationale: security-relevant skills drift fastest; math/formal methods are more durable.

## What v0 does NOT have

- No emissions / staking rewards
- No fee market
- No delegation
- No committees, no on-chain votes, no governance
- No bonding curves or AMMs
- No cross-chain bridging
- No liquid staking derivative

All deferred; see `ROADMAP.md`.
