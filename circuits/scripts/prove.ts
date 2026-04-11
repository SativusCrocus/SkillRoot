#!/usr/bin/env tsx
// prove.ts — thin wrapper around snarkjs for the math circuit
//
// Usage:
//   tsx prove.ts <inputJson> <wasmPath> <zkeyPath> <outDir>
//
// Emits: proof.json, public.json, and calldata.json (a calldata-formatted
// object with a/b/c/pubSignals ready for AttestationEngine.submitClaim).
//
// Note: public.json contains the full public-signals array exactly as the
// verifier expects. When passing to AttestationEngine, drop signal[0]
// (bindingHash) because the engine prepends its own version; pass the
// remaining 3 (base, modulus, result) as `circuitSignals`.

import * as fs from "fs";
import * as path from "path";

async function main() {
    const [inputPath, wasmPath, zkeyPath, outDir] = process.argv.slice(2);
    if (!inputPath || !wasmPath || !zkeyPath || !outDir) {
        console.error(
            "usage: tsx prove.ts <inputJson> <wasmPath> <zkeyPath> <outDir>"
        );
        process.exit(2);
    }
    fs.mkdirSync(outDir, { recursive: true });

    // @ts-ignore — snarkjs ships untyped
    const snarkjs = await import("snarkjs");
    const input = JSON.parse(fs.readFileSync(inputPath, "utf8"));

    console.error("generating witness + proof...");
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(
        input, wasmPath, zkeyPath
    );

    fs.writeFileSync(
        path.join(outDir, "proof.json"),
        JSON.stringify(proof, null, 2)
    );
    fs.writeFileSync(
        path.join(outDir, "public.json"),
        JSON.stringify(publicSignals, null, 2)
    );

    // Convert to Solidity calldata shape
    const a: [string, string] = [proof.pi_a[0], proof.pi_a[1]];
    // snarkjs emits b in reversed column order for the BN254 pairing
    const b: [[string, string], [string, string]] = [
        [proof.pi_b[0][1], proof.pi_b[0][0]],
        [proof.pi_b[1][1], proof.pi_b[1][0]],
    ];
    const c: [string, string] = [proof.pi_c[0], proof.pi_c[1]];

    // AttestationEngine expects circuitSignals = publicSignals.slice(1)
    // because signal[0] is the contract-computed bindingHash.
    const circuitSignals = publicSignals.slice(1);

    const calldata = {
        a, b, c,
        pubSignals: publicSignals,
        circuitSignals,
    };
    fs.writeFileSync(
        path.join(outDir, "calldata.json"),
        JSON.stringify(calldata, null, 2)
    );
    console.error(`wrote ${outDir}/proof.json, public.json, calldata.json`);
    console.error(`publicSignals[0] (bindingHash) = ${publicSignals[0]}`);
    console.error(`circuitSignals = ${JSON.stringify(circuitSignals)}`);
}

main().then(() => process.exit(0)).catch(e => {
    console.error(e);
    process.exit(1);
});
