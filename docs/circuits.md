# Circuits

v0 ships **exactly one** circuit: `math.circom` (modular exponentiation). Additional circuits are deferred to v1 (see `ROADMAP.md`).

## math.circom

### Statement

Prove knowledge of `exponent` (32 bits, private) such that:

```
base^exponent mod modulus == result
```

over 32-bit `base`, `modulus`, `result` (public).

### Public signals (order matters)

| index | name | source |
|-------|------|--------|
| 0 | `bindingHash` | contract-computed `keccak256(abi.encode(msg.sender, challengeId)) & MASK248` |
| 1 | `base` | 32-bit |
| 2 | `modulus` | 32-bit |
| 3 | `result` | 32-bit |

The circuit exposes `bindingHash` via the `BindingPassthrough` template (a no-op `out <== in`), which documents the convention without adding constraints.

### Algorithm

Left-to-right square-and-multiply, 32 iterations:

```
acc ← 1
for i in 31..0:
    acc ← (acc * acc) mod modulus       // square step
    if exp.bit[i]:
        acc ← (acc * base) mod modulus  // conditional multiply
```

Each modular reduction is witnessed as `(q, r)` with the constraint `val == q * modulus + r, 0 <= r < modulus`. `q` is range-checked to 66 bits (enough for `preSq = acc*acc` up to 64 bits, plus slack); `r` is range-checked to 32 bits. A `LessThan(33)` comparator asserts `r < modulus`.

### Constraint budget

| Element | Count |
|---------|-------|
| Num2Bits(32) for exponent/base/mod/result | 128 |
| BindingPassthrough | 1 |
| Per step × 32: Num2Bits(66) q + Num2Bits(32) r + LessThan(33) + val check, ×2 | ~270 × 32 = ~8640 |
| **Total non-linear** | **8671** (measured) |

Fits comfortably in `pot14` (2^14 = 16384 constraints).

### Private inputs

```
exponent        : 1   (32-bit)
qSq[32], rSq[32]: per-step square modulo witness
qMul[32],rMul[32]: per-step multiply modulo witness
```

Total private: 129 signals.

## Build pipeline

```bash
scripts/ceremony.sh              # downloads pot14_final.ptau
circuits/math/build.sh           # compile + groth16 setup + contribution + verifier
```

Emits to `circuits/math/build/`:

- `math.r1cs`
- `math_js/math.wasm`
- `math_final.zkey`
- `verification_key.json`
- `MathVerifier.sol` (snarkjs-generated, renamed to `MathGroth16Verifier`)

## Trusted setup

- **Phase 1**: Hermez Powers of Tau `pot14_final.ptau`, publicly audited.
- **Phase 2**: single-party contribution by the v0 deployer. Entropy from `openssl rand -hex 32`. **Not a multi-party ceremony.** Pre-mainnet, a real ceremony must be run with ≥3 external contributors (see `threat-model.md` R2).

## Proving

Off-chain proving uses `circuits/scripts/prove.ts` (wraps `snarkjs.groth16.fullProve`) or the CLI command `skr solve`.

Expected throughput on an M1 MacBook: ~2 s per proof for the 8.6k-constraint circuit.
