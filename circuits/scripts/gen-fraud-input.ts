#!/usr/bin/env tsx
// gen-fraud-input.ts — produces a valid fraud.circom witness that disproves
// a (base, modulus, claimedResult) claim by exhibiting a true exponent whose
// modexp yields a DIFFERENT actualResult.
//
// Usage:
//   tsx gen-fraud-input.ts <bindingHash> <base> <trueExponent> <modulus> <claimedResult> [outPath]
//
// The binding hash must match what AttestationEngine computed for the
// challenged claim's (claimant, challengeId). Off-chain tools can call
// `AttestationEngine.bindingHashOf(address, uint256)` to retrieve it.
//
// Note: "trueExponent" is any exponent the prover knows that yields a result
// different from claimedResult. The script computes actualResult = base^exp
// mod modulus and fails if it happens to equal claimedResult (because then
// there is no fraud to prove).

import * as fs from "fs";

// BN254 scalar field prime r.
const BN254_R =
    21888242871839275222246405745257275088548364400416034343698204186575808495617n;

function modexp(base: bigint, exp: bigint, m: bigint): bigint {
    let acc = 1n;
    let b = base % m;
    let e = exp;
    while (e > 0n) {
        if (e & 1n) acc = (acc * b) % m;
        b = (b * b) % m;
        e >>= 1n;
    }
    return acc;
}

// Extended Euclidean algorithm for modular inverse in the BN254 scalar field.
function modInverse(a: bigint, p: bigint): bigint {
    let [oldR, r] = [((a % p) + p) % p, p];
    let [oldS, s] = [1n, 0n];
    while (r !== 0n) {
        const q = oldR / r;
        [oldR, r] = [r, oldR - q * r];
        [oldS, s] = [s, oldS - q * s];
    }
    if (oldR !== 1n) throw new Error("no inverse: value is zero mod p");
    return ((oldS % p) + p) % p;
}

interface Input {
    bindingHash: string;
    base: string;
    modulus: string;
    claimedResult: string;
    exponent: string;
    actualResult: string;
    inv: string;
    qSq: string[];
    rSq: string[];
    qMul: string[];
    rMul: string[];
}

function buildInput(
    bindingHash: bigint,
    base: bigint,
    exponent: bigint,
    modulus: bigint,
    claimedResult: bigint
): Input {
    if (modulus <= 1n) throw new Error("modulus must be > 1");
    if (base >= 1n << 32n || modulus >= 1n << 32n || exponent >= 1n << 32n) {
        throw new Error("base/modulus/exponent must fit in 32 bits");
    }
    if (claimedResult >= 1n << 32n) {
        throw new Error("claimedResult must fit in 32 bits");
    }

    const bits: number[] = [];
    for (let i = 0; i < 32; i++) {
        bits.push(Number((exponent >> BigInt(i)) & 1n));
    }

    let acc = 1n;
    const qSq: string[] = [];
    const rSq: string[] = [];
    const qMul: string[] = [];
    const rMul: string[] = [];

    for (let i = 0; i < 32; i++) {
        const bi = 31 - i;
        const bit = bits[bi];

        const preSq = acc * acc;
        const postSq = preSq % modulus;
        const qS = preSq / modulus;
        qSq.push(qS.toString());
        rSq.push(postSq.toString());

        const preMul = postSq * base;
        const postMul = preMul % modulus;
        const qM = preMul / modulus;
        qMul.push(qM.toString());
        rMul.push(postMul.toString());

        acc = bit === 1 ? postMul : postSq;
    }

    const actualResult = acc;
    const expectedResult = modexp(base, exponent, modulus);
    if (actualResult !== expectedResult) {
        throw new Error(
            `internal mismatch: got ${actualResult}, expected ${expectedResult}`
        );
    }
    if (actualResult === claimedResult) {
        throw new Error(
            "no fraud: actualResult equals claimedResult; the original claim would be correct for this exponent"
        );
    }

    // Witness the non-equality via a multiplicative inverse in BN254's scalar
    // field. diff = (actualResult - claimedResult) mod r  (never zero here).
    const diff = ((actualResult - claimedResult) % BN254_R + BN254_R) % BN254_R;
    const inv = modInverse(diff, BN254_R);

    return {
        bindingHash: bindingHash.toString(),
        base: base.toString(),
        modulus: modulus.toString(),
        claimedResult: claimedResult.toString(),
        exponent: exponent.toString(),
        actualResult: actualResult.toString(),
        inv: inv.toString(),
        qSq,
        rSq,
        qMul,
        rMul,
    };
}

function main() {
    const [bhArg, baseArg, expArg, modArg, claimedArg, outPath] =
        process.argv.slice(2);
    if (!bhArg || !baseArg || !expArg || !modArg || !claimedArg) {
        console.error(
            "usage: tsx gen-fraud-input.ts <bindingHash> <base> <trueExponent> <modulus> <claimedResult> [outPath]"
        );
        process.exit(2);
    }
    const input = buildInput(
        BigInt(bhArg),
        BigInt(baseArg),
        BigInt(expArg),
        BigInt(modArg),
        BigInt(claimedArg)
    );
    const json = JSON.stringify(input, null, 2);
    if (outPath) {
        fs.writeFileSync(outPath, json);
        console.error(`wrote ${outPath}`);
    } else {
        console.log(json);
    }
}

main();
