# Tokenomics — SKR

## Supply

**Fixed 100,000,000 SKR, minted once at genesis.** No `mint()` exists. Supply only decreases (via slashing burns to 0xdead).

```
INITIAL_SUPPLY = 100_000_000 ether   // 18 decimals
```

## Distribution (v0 genesis)

| Allocation | % | Notes |
|------------|---|-------|
| Governance treasury | 100% | entire supply sent to the `Governance` contract at deploy, managed by on-chain proposals |

v0 has no investor round, no team vesting, no airdrop. The bootstrapping plan (`bootstrapping.md`) outlines how early validators earn stake via operator grants approved by governance.

## Staking

```
MIN_STAKE    = 1_000 SKR
UNBOND_DELAY = 14 days
```

Validators bond SKR to become eligible for sortition. The committee-draw probability is proportional to stake via linear stake-weighted sampling.

## Slashing

```
SLASH_LIVENESS_BPS     = 100  // 1%
SLASH_EQUIVOCATION_BPS = 500  // 5%
```

- **Liveness slash** — any committee member who fails to vote within the 24h window loses 1% of their stake.
- **Equivocation slash** — any committee member whose vote direction disagrees with the final outcome loses 5%.
- **Burn** — all slashed tokens go to `0xdead`. The token is deflationary under adversarial behavior.

Below `MIN_STAKE`, a validator is automatically removed from the validators[] array.

## Challenge bond

```
PROPOSER_BOND = 10_000 SKR
```

Anyone can propose a new challenge by posting the bond. Governance either `activate`s (bond refunded) or `reject`s (bond burned). This keeps proposal spam costly.

## Game theory

### Validator incentives

A validator decides whether to vote YES or NO on a claim. Without any direct reward (v0 has no emissions), the dominant strategy is to vote **honestly** because:

1. **Downside** — wrong votes forfeit 5% of stake per claim. Liveness-skipping forfeits 1%.
2. **No upside for lying** — silent ≠ honest in v0; silent is still slashed.
3. **Schelling-point coordination** — the honest proof either verifies or doesn't. There's no hidden information the validator needs to guess.

### Attacker model

For an attacker to force acceptance of a bogus claim:

- They need `ceil(7 * 2/3) = 5` Byzantine validators on a 7-member committee.
- With committee drawn stake-weighted from `n` validators, the probability of 5 colluding validators being drawn is approximately `C(n, 5) · (f/n)^5 / C(n_total, 5)` where `f` is the colluder fraction.
- For n=50 and f=10% colluders, that's <0.001%.
- Even if the attacker wins, each colluder loses 5% of stake on the (now-exposed) malicious vote.

A higher committee size would raise the bar further but also raises gas cost per claim. 7 is the v0 compromise — reviewed for v1.

### Honest validator economics

v0 has no direct reward emissions. Early validator operators are grant-funded by the Governance treasury (see `bootstrapping.md`). A future fee market (paid in SKR for attestation submission) is planned for v1.

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

- No emissions / staking rewards (treasury grants only)
- No fee market
- No delegation (validator = SKR holder; no liquid delegation)
- No bonding curves or AMMs
- No cross-chain bridging
- No liquid staking derivative

All deferred to v1, documented in `ROADMAP.md`.
