# Contracts Reference (v0.2.0-no-vote)

All contracts live in `contracts/src/`. Built with Foundry + solc 0.8.24 + OpenZeppelin v5.0.2. The v0.2.0-no-vote deployment ships **8 canonical contracts** (see `deployments/base-sepolia.json`).

## SKRToken.sol

ERC20 + ERC20Permit + ERC20Votes. **Fixed supply**, no `mint()`. The ERC20Votes base is retained solely for future optional-governance hooks; v0 has no on-chain voting pathway.

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

- `bond(amount)` — pulls tokens, adds to validator set if new.
- `requestUnbond(amount)` — starts 14-day unlock; must either exit fully or stay ≥ MIN_STAKE.
- `withdraw()` — after the delay elapses.
- `slash(validator, amount)` — burns to 0xdead; gated to engine paths.

In v0.2.0-no-vote the staking set is used to gate eligibility for submitting fraud proofs (`FRAUD_PROVER_MIN_STAKE = 1_000 ether`). No committee sampling, no liveness/equivocation slashing.

## ChallengeRegistry.sol

```
PROPOSER_BOND = 10_000 ether
Domain        = { ALGO, FORMAL_VER, APPLIED_MATH, SEC_CODE }
Status        = { PENDING, ACTIVE, DEPRECATED, REJECTED }
```

Lifecycle: `propose` (anyone, pays bond) → after an inactivity window, **permissionless** `activate` or `reject`. No governance vote, no admin key.

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
CHALLENGE_WINDOW         = 24 hours
CLAIM_BOND               = 100 ether
FRAUD_PROVER_MIN_STAKE   = 1_000 ether
BURN_ADDRESS             = 0x...dEaD
```

### D2 revision

```solidity
uint256 bindingHash =
    uint256(keccak256(abi.encode(msg.sender, challengeId))) & ((1 << 248) - 1);
// prepend to circuitSignals as signal[0], then call verifier
```

The 248-bit mask ensures `bindingHash < r` where `r` is the BN254 scalar field order (~2^254). Fraud proofs use the **claim's** (claimant, challengeId) as inputs, binding the proof to the specific submission it refutes.

### Flow

1. `submitClaim(challengeId, a, b, c, circuitSignals, artifactCID)` → `claimId`; claim is `PENDING`, 100 SKR bond locked, `challengeDeadline = now + 24h`.
2. Inside the 24h window, any address with ≥ `FRAUD_PROVER_MIN_STAKE` in the vault may call `submitFraudProof(claimId, a, b, c, fraudSignals)`. If valid:
   - claim → `FINALIZED_REJECT`
   - 50% of bond to prover, 50% burned
   - `FraudProven` + `ClaimFinalized(accepted=false)` emitted
3. Once the window closes with no successful fraud proof, anyone may call `finalizeClaim(claimId)`:
   - claim → `FINALIZED_ACCEPT`
   - bond returned to claimant
   - `AttestationStore.record(...)` written
   - `ClaimFinalized(accepted=true)` emitted

No committees, no votes, no governance path.

## MathVerifierAdapter.sol / FraudVerifierAdapter.sol

Thin shims. `IZKVerifier.verifyProof` takes dynamic `uint256[] calldata pubSignals`; snarkjs emits verifiers whose signature is fixed-size (`uint256[N] calldata input`). Each adapter unpacks the first N public signals and reverts with `WrongSignalLength` otherwise.

## QueryGateway.sol

Stable external read surface. `verify(address claimant) → uint256[4]` returns the decayed score per domain from `AttestationStore`. The only public API dApps need to integrate with SkillRoot.
