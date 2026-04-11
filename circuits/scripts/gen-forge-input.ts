#!/usr/bin/env tsx
// gen-forge-input.ts — produces a valid forge_challenge.circom witness
//
// Usage:
//   tsx gen-forge-input.ts <bindingHash> <targetCircuitHash> <exploitTag> <v0> <v1> <v2> <v3> [outPath]
//
// The binding hash must match what ForgeGuard will compute:
//   ForgeGuard.forgeBindingHashOf(address, targetChallengeId)
//
// The exploit commitment is computed as Poseidon(v0, v1, v2, v3) using
// circomlibjs. Install it:  npm install circomlibjs
//
// For break proofs, use ForgeGuard.breakBindingHashOf(address, forgeId).

import * as fs from "fs";

interface ForgeInput {
    bindingHash: string;
    targetCircuitHash: string;
    exploitTag: string;
    exploitCommitment: string;
    exploitVector: string[];
}

async function buildInput(
    bindingHash: bigint,
    targetCircuitHash: bigint,
    exploitTag: bigint,
    exploitVector: [bigint, bigint, bigint, bigint],
): Promise<ForgeInput> {
    // Dynamic import — circomlibjs must be installed in the project
    let buildPoseidon: any;
    try {
        const mod = await import("circomlibjs");
        buildPoseidon = mod.buildPoseidon;
    } catch {
        console.error(
            "circomlibjs not found. Install it: npm install circomlibjs\n" +
            "Falling back to placeholder commitment (tests only).",
        );
        // Fallback: simple hash for testing (NOT production-safe)
        const placeholder = exploitVector.reduce((a, b) => a ^ b, 0n);
        return {
            bindingHash: bindingHash.toString(),
            targetCircuitHash: targetCircuitHash.toString(),
            exploitTag: exploitTag.toString(),
            exploitCommitment: placeholder.toString(),
            exploitVector: exploitVector.map((v) => v.toString()),
        };
    }

    const poseidon = await buildPoseidon();
    const hash = poseidon(exploitVector.map((v) => v));
    const commitment = poseidon.F.toString(hash);

    return {
        bindingHash: bindingHash.toString(),
        targetCircuitHash: targetCircuitHash.toString(),
        exploitTag: exploitTag.toString(),
        exploitCommitment: commitment,
        exploitVector: exploitVector.map((v) => v.toString()),
    };
}

async function main() {
    const args = process.argv.slice(2);
    if (args.length < 7) {
        console.error(
            "usage: tsx gen-forge-input.ts <bindingHash> <targetCircuitHash> " +
            "<exploitTag> <v0> <v1> <v2> <v3> [outPath]",
        );
        process.exit(2);
    }

    const [bhArg, tchArg, tagArg, v0Arg, v1Arg, v2Arg, v3Arg, outPath] = args;

    const input = await buildInput(
        BigInt(bhArg),
        BigInt(tchArg),
        BigInt(tagArg),
        [BigInt(v0Arg), BigInt(v1Arg), BigInt(v2Arg), BigInt(v3Arg)],
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
