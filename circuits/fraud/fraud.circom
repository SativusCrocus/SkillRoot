pragma circom 2.1.9;

include "bitify.circom";
include "comparators.circom";
include "../common/claimant_binding.circom";

// Fraud — reuses the math modexp scaffold to prove that a claimed result is
// WRONG for a given (base, modulus). The prover supplies an exponent and a
// witnessed actualResult such that
//     actualResult == base^exponent mod modulus
//     actualResult != claimedResult
// Non-equality is witnessed via a multiplicative inverse:
//     (actualResult - claimedResult) * inv == 1
//
// Public signals (in order, matches FraudVerifierAdapter):
//   0. bindingHash    — pass-through from contract-side keccak, bound to the
//                       challenged claim's (claimant, challengeId)
//   1. base           — same base as the original claim
//   2. modulus        — same modulus as the original claim
//   3. claimedResult  — the result the original claim asserted
//
// Private signals:
//   - exponent (32 bits)
//   - actualResult (32 bits)
//   - inv  — multiplicative inverse of (actualResult - claimedResult)
//   - qSq[32], rSq[32], qMul[32], rMul[32] — per-step witnessed reductions
//
// This is intentionally minimal and mirrors math.circom for reviewability.

template ModReduce(NBITS_Q, NBITS_R) {
    signal input  val;
    signal input  m;
    signal input  q;
    signal input  r;
    signal output out;

    component qbits = Num2Bits(NBITS_Q);
    qbits.in <== q;
    component rbits = Num2Bits(NBITS_R);
    rbits.in <== r;

    component lt = LessThan(33);
    lt.in[0] <== r;
    lt.in[1] <== m;
    lt.out === 1;

    val === q * m + r;

    out <== r;
}

template Fraud() {
    // Public
    signal input  bindingHash;
    signal input  base;
    signal input  modulus;
    signal input  claimedResult;

    // Private
    signal input  exponent;
    signal input  actualResult;
    signal input  inv;
    signal input  qSq[32];
    signal input  rSq[32];
    signal input  qMul[32];
    signal input  rMul[32];

    // Decompose exponent into 32 bits (little-endian)
    component eBits = Num2Bits(32);
    eBits.in <== exponent;

    // Range checks on public and witnessed 32-bit values
    component baseBits = Num2Bits(32);
    baseBits.in <== base;
    component modBits = Num2Bits(32);
    modBits.in <== modulus;
    component resBits = Num2Bits(32);
    resBits.in <== claimedResult;
    component actBits = Num2Bits(32);
    actBits.in <== actualResult;

    // Etch bindingHash as a public signal via the shared passthrough template.
    component passthrough = BindingPassthrough();
    passthrough.in <== bindingHash;

    // Accumulator chain (identical to math.circom)
    signal acc[33];
    signal postSq[32];
    signal preSq[32];
    signal preMul[32];
    signal postMul[32];

    acc[0] <== 1;

    component squareReduce[32];
    component multiplyReduce[32];

    for (var i = 0; i < 32; i++) {
        var bi = 31 - i;
        var bit = eBits.out[bi];

        preSq[i] <== acc[i] * acc[i];
        squareReduce[i] = ModReduce(66, 32);
        squareReduce[i].val <== preSq[i];
        squareReduce[i].m   <== modulus;
        squareReduce[i].q   <== qSq[i];
        squareReduce[i].r   <== rSq[i];
        postSq[i] <== squareReduce[i].out;

        preMul[i] <== postSq[i] * base;
        multiplyReduce[i] = ModReduce(66, 32);
        multiplyReduce[i].val <== preMul[i];
        multiplyReduce[i].m   <== modulus;
        multiplyReduce[i].q   <== qMul[i];
        multiplyReduce[i].r   <== rMul[i];
        postMul[i] <== multiplyReduce[i].out;

        acc[i + 1] <== postSq[i] + bit * (postMul[i] - postSq[i]);
    }

    // modexp(base, exponent, modulus) matches the witnessed actualResult
    acc[32] === actualResult;

    // actualResult != claimedResult, witnessed by an inverse of the difference
    signal diff;
    diff <== actualResult - claimedResult;
    diff * inv === 1;
}

component main {public [bindingHash, base, modulus, claimedResult]} = Fraud();
