pragma circom 2.1.9;

include "bitify.circom";
include "comparators.circom";
include "../common/claimant_binding.circom";

// Math — proves knowledge of a 32-bit `exponent` such that
//     base^exponent mod modulus == result
// over 32-bit base, modulus, result. ~5k constraints.
//
// Public signals (in order):
//   0. bindingHash — pass-through from contract-side keccak
//   1. base
//   2. modulus
//   3. result
//
// Private signals:
//   - exponent (32 bits)
//   - q[i], r[i] — witnessed quotient + remainder per square-and-multiply step
//
// Algorithm: left-to-right square-and-multiply. At each of 32 iterations i
// (from high bit to low bit):
//   acc  ← acc * acc                    (mod modulus)
//   acc  ← exponent.bit[i] ? acc * base : acc
// Modular reduction uses witnessed (q, r) with:
//   expr = q * modulus + r,  0 <= r < modulus
// To keep this template simple we bound the working accumulator by
// constraining r to be 32 bits and q to be 64 bits per step (both
// fit within the BN254 scalar field at ~100 bits after multiplying by
// modulus).
//
// Note: this is a self-contained test circuit meant to exercise the full
// proving pipeline on a small domain. Do not use it as a production modexp
// primitive. For real cryptographic exponents use a bigint library.

template ModReduce(NBITS_Q, NBITS_R) {
    // constrains: val == q * m + r, 0 <= r < m, q fits in NBITS_Q bits
    signal input  val;
    signal input  m;
    signal input  q;
    signal input  r;
    signal output out;

    // Range check q and r
    component qbits = Num2Bits(NBITS_Q);
    qbits.in <== q;
    component rbits = Num2Bits(NBITS_R);
    rbits.in <== r;

    // r < m  (both fit in 32 bits so a 33-bit LessThan is safe)
    component lt = LessThan(33);
    lt.in[0] <== r;
    lt.in[1] <== m;
    lt.out === 1;

    // Enforce the division identity
    val === q * m + r;

    out <== r;
}

template Math() {
    // Public
    signal input  bindingHash;
    signal input  base;
    signal input  modulus;
    signal input  result;

    // Private
    signal input  exponent;
    // 32 square steps + 32 multiply steps = 64 reductions
    signal input  qSq[32];
    signal input  rSq[32];
    signal input  qMul[32];
    signal input  rMul[32];

    // Decompose exponent into 32 bits (little-endian)
    component eBits = Num2Bits(32);
    eBits.in <== exponent;

    // Range checks on public inputs (32-bit)
    component baseBits = Num2Bits(32);
    baseBits.in <== base;
    component modBits = Num2Bits(32);
    modBits.in <== modulus;
    component resBits = Num2Bits(32);
    resBits.in <== result;

    // Pass-through so bindingHash is etched as a public signal
    component passthrough = BindingPassthrough();
    passthrough.in <== bindingHash;

    // Accumulator chain: acc[0] = 1, then for each bit (MSB→LSB)
    // postSq  = (acc * acc) mod modulus
    // postMul = bit ? (postSq * base) mod modulus : postSq
    signal acc[33];
    signal postSq[32];
    signal preSq[32];
    signal preMul[32];
    signal postMul[32];

    acc[0] <== 1;

    component squareReduce[32];
    component multiplyReduce[32];

    for (var i = 0; i < 32; i++) {
        // bit index going MSB → LSB
        var bi = 31 - i;
        var bit = eBits.out[bi];

        // --- square step ---
        preSq[i] <== acc[i] * acc[i];
        squareReduce[i] = ModReduce(66, 32);
        squareReduce[i].val <== preSq[i];
        squareReduce[i].m   <== modulus;
        squareReduce[i].q   <== qSq[i];
        squareReduce[i].r   <== rSq[i];
        postSq[i] <== squareReduce[i].out;

        // --- conditional multiply step ---
        // preMul = postSq * base
        preMul[i] <== postSq[i] * base;
        multiplyReduce[i] = ModReduce(66, 32);
        multiplyReduce[i].val <== preMul[i];
        multiplyReduce[i].m   <== modulus;
        multiplyReduce[i].q   <== qMul[i];
        multiplyReduce[i].r   <== rMul[i];
        postMul[i] <== multiplyReduce[i].out;

        // acc[i+1] = bit ? postMul[i] : postSq[i]
        acc[i + 1] <== postSq[i] + bit * (postMul[i] - postSq[i]);
    }

    // Final constraint: the accumulator matches result
    acc[32] === result;
}

component main {public [bindingHash, base, modulus, result]} = Math();
