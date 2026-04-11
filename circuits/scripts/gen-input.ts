#!/usr/bin/env tsx
// gen-input.ts — produces a valid math.circom witness from (base, exp, modulus)
//
// Usage:
//   tsx gen-input.ts <bindingHash> <base> <exponent> <modulus> > input.json
//
// The binding hash must match what AttestationEngine will compute for the
// claimant + challengeId at submission time. Off-chain tools can call
// `AttestationEngine.bindingHashOf(address, uint256)` to retrieve it as a
// decimal string.

import * as fs from "fs";

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

interface Input {
    bindingHash: string;
    base: string;
    modulus: string;
    result: string;
    exponent: string;
    qSq: string[];
    rSq: string[];
    qMul: string[];
    rMul: string[];
}

function buildInput(bindingHash: bigint, base: bigint, exponent: bigint, modulus: bigint): Input {
    if (modulus <= 1n) throw new Error("modulus must be > 1");
    if (base >= 1n << 32n || modulus >= 1n << 32n || exponent >= 1n << 32n) {
        throw new Error("base/modulus/exponent must fit in 32 bits");
    }

    // Expand exponent to 32 bits little-endian, then iterate MSB→LSB
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

    const result = acc;
    const expectedResult = modexp(base, exponent, modulus);
    if (result !== expectedResult) {
        throw new Error(
            `internal mismatch: got ${result}, expected ${expectedResult}`
        );
    }

    return {
        bindingHash: bindingHash.toString(),
        base: base.toString(),
        modulus: modulus.toString(),
        result: result.toString(),
        exponent: exponent.toString(),
        qSq,
        rSq,
        qMul,
        rMul,
    };
}

function main() {
    const [bhArg, baseArg, expArg, modArg, outPath] = process.argv.slice(2);
    if (!bhArg || !baseArg || !expArg || !modArg) {
        console.error(
            "usage: tsx gen-input.ts <bindingHash> <base> <exponent> <modulus> [outPath]"
        );
        process.exit(2);
    }
    const input = buildInput(BigInt(bhArg), BigInt(baseArg), BigInt(expArg), BigInt(modArg));
    const json = JSON.stringify(input, null, 2);
    if (outPath) {
        fs.writeFileSync(outPath, json);
        console.error(`wrote ${outPath}`);
    } else {
        console.log(json);
    }
}

main();
