# Contracts Reference

All contracts live in `contracts/src/`. Built with Foundry + solc 0.8.24 + OpenZeppelin v5.0.2.

## SKRToken.sol

ERC20 + ERC20Permit + ERC20Votes. **Fixed supply**, no `mint()`.

```
INITIAL_SUPPLY = 100_000_000 ether
clock()        = block.timestamp   // OZ v5 timestamp mode
CLOCK_MODE()   = "mode=timestamp"
```

## StakingVault.sol

```
MIN_STAKE    = 1_000 ether
UNBOND_DELAY = 14 days
BURN_ADDRESS = 0x...dEaD
```

- `bond(amount)` — pulls tokens, adds to dense validators[] if new.
- `requestUnbond(amount)` — starts 14-day unlock; must either exit fully or stay ≥ MIN_STAKE.
- `withdraw()` — after the delay elapses.
- `slash(validator, amount)` — **onlyEngine**; burns to 0xdead; removes from validators[] if below MIN_STAKE.

## ChallengeRegistry.sol

```
PROPOSER_BOND = 10_000 ether
Domain        = { ALGO, FORMAL_VER, APPLIED_MATH, SEC_CODE }
Status        = { PENDING, ACTIVE, DEPRECATED, REJECTED }
```

Lifecycle: `propose` (anyone, pays bond) → `activate` (governance, bond refunded) or `reject` (governance, bond burned) → eventually `deprecate` (governance).

## Sortition.sol

```
COMMITTEE_SIZE = 7
REVEAL_DELAY   = 4     // blocks
REVEAL_WINDOW  = 240   // blocks (~8 min on Base)
```

Entropy: `blockhash(submissionBlock + 4)`. Linear O(k·n) sampling over a mutable stake snapshot. Array length shrinks via inline assembly if fewer than COMMITTEE_SIZE validators were drawn.

## AttestationStore.sol

```
HL_ALGO         = 730 days
HL_FORMAL_VER   = 1095 days
HL_APPLIED_MATH = 1095 days
HL_SEC_CODE     = 365 days
```

Discrete half-life:
```
age    = now - recordTimestamp
shifts = age / half_life
modAge = age mod half_life
weight = baseWeight >> shifts
adj    = weight * (2*HL - modAge) / (2*HL)
```

Shifts > 64 are treated as fully decayed (return 0) to avoid astronomical right-shifts.

## AttestationEngine.sol

```
VOTE_WINDOW            = 24 hours
QUORUM_BPS             = 6_666   // 66.66%
SLASH_EQUIVOCATION_BPS = 500     // 5%
SLASH_LIVENESS_BPS     = 100     // 1%
```

### D2 revision

```solidity
uint256 bindingHash =
    uint256(keccak256(abi.encode(msg.sender, challengeId))) & ((1 << 248) - 1);
// prepend to circuitSignals as signal[0], then call verifier
```

The 248-bit mask ensures `bindingHash < r` where `r` is the BN254 scalar field order (~2^254).

### Flow

1. `submitClaim(challengeId, a, b, c, circuitSignals, artifactCID)` → `claimId`
2. wait REVEAL_DELAY blocks → `drawCommittee(claimId)`
3. each committee member calls `vote(claimId, yes)` within VOTE_WINDOW
4. anyone calls `finalize(claimId)` after vote window closes:
   - silent members → liveness slash (1% of stake)
   - voters whose direction disagrees with outcome → equivocation slash (5% of stake)
   - if accepted, write `AttestationStore.record`

## Governance.sol

```
VOTING_PERIOD = 5 days
QUORUM_BPS    = 400  // 4%
```

Uses `token.getPastVotes` and `getPastTotalSupply` at a snapshot one clock tick before the proposal. `receive()` is payable; proposals can send ETH.

**No timelock in v0** — deferred to v1 (see ROADMAP.md).

## MathVerifierAdapter.sol

Thin shim. `IZKVerifier.verifyProof` takes dynamic `uint256[] calldata pubSignals`; snarkjs emits a verifier whose signature is fixed-size (`uint256[4] calldata input`). The adapter unpacks the first 4 public signals and reverts with `WrongSignalLength` otherwise.
