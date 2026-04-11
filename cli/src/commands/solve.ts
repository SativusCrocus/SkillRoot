import { Command } from 'commander';
import kleur from 'kleur';
import ora from 'ora';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { loadConfig, publicClient, walletClient } from '../config.js';
import { attestationEngineAbi } from '../abis.js';
// @ts-ignore snarkjs has no types
import * as snarkjs from 'snarkjs';

interface SolveOpts {
  base: string;
  exponent: string;
  modulus: string;
  wasm: string;
  zkey: string;
  outDir: string;
}

function modexp(b: bigint, e: bigint, m: bigint): bigint {
  let r = 1n; let bb = b % m; let ee = e;
  while (ee > 0n) { if (ee & 1n) r = (r * bb) % m; bb = (bb * bb) % m; ee >>= 1n; }
  return r;
}

function buildInput(bindingHash: bigint, base: bigint, exp: bigint, m: bigint) {
  const bits: number[] = [];
  for (let i = 0; i < 32; i++) bits.push(Number((exp >> BigInt(i)) & 1n));

  let acc = 1n;
  const qSq: string[] = [];
  const rSq: string[] = [];
  const qMul: string[] = [];
  const rMul: string[] = [];
  for (let i = 0; i < 32; i++) {
    const bi = 31 - i;
    const bit = bits[bi];
    const preSq = acc * acc;
    const postSq = preSq % m;
    qSq.push((preSq / m).toString()); rSq.push(postSq.toString());
    const preMul = postSq * base;
    const postMul = preMul % m;
    qMul.push((preMul / m).toString()); rMul.push(postMul.toString());
    acc = bit === 1 ? postMul : postSq;
  }
  return {
    bindingHash: bindingHash.toString(),
    base: base.toString(),
    modulus: m.toString(),
    result: acc.toString(),
    exponent: exp.toString(),
    qSq, rSq, qMul, rMul,
  };
}

export const solveCmd = new Command('solve')
  .description('generate a zk proof for the math (modexp) challenge')
  .argument('<challengeId>', 'challenge id (e.g. 1 for math)')
  .requiredOption('--base <base>', '32-bit base')
  .requiredOption('--exp <exp>', '32-bit exponent')
  .requiredOption('--mod <mod>', '32-bit modulus')
  .option('--wasm <path>', 'path to math.wasm', './circuits/math/build/math_js/math.wasm')
  .option('--zkey <path>', 'path to math_final.zkey', './circuits/math/build/math_final.zkey')
  .option('--out <dir>', 'output directory', './proofs')
  .action(async (challengeIdArg: string, opts: any) => {
    const cfg = loadConfig();
    const pub = publicClient(cfg);
    const wallet = walletClient(cfg);
    const challengeId = BigInt(challengeIdArg);

    const spin = ora('computing binding hash...').start();
    const binding = await pub.readContract({
      address: cfg.contracts.engine,
      abi: attestationEngineAbi,
      functionName: 'bindingHashOf',
      args: [wallet.account.address, challengeId],
    });
    spin.succeed(`bindingHash = ${binding}`);

    const base = BigInt(opts.base);
    const exp = BigInt(opts.exp);
    const mod = BigInt(opts.mod);
    const expected = modexp(base, exp, mod);
    console.log(kleur.gray(`sanity: ${base}^${exp} mod ${mod} = ${expected}`));

    const input = buildInput(binding as bigint, base, exp, mod);
    fs.mkdirSync(opts.out, { recursive: true });
    const inputPath = path.join(opts.out, `input-${challengeId}.json`);
    fs.writeFileSync(inputPath, JSON.stringify(input, null, 2));

    const spin2 = ora('generating Groth16 proof...').start();
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(
      input, opts.wasm, opts.zkey
    );
    spin2.succeed('proof generated');

    // Convert to Solidity calldata shape
    const calldata = {
      a: [proof.pi_a[0], proof.pi_a[1]],
      b: [
        [proof.pi_b[0][1], proof.pi_b[0][0]],
        [proof.pi_b[1][1], proof.pi_b[1][0]],
      ],
      c: [proof.pi_c[0], proof.pi_c[1]],
      pubSignals: publicSignals,
      circuitSignals: publicSignals.slice(1),
    };
    const outPath = path.join(opts.out, `calldata-${challengeId}.json`);
    fs.writeFileSync(outPath, JSON.stringify(calldata, null, 2));
    console.log(kleur.green(`wrote ${outPath}`));
    console.log(kleur.gray(`next: skr submit ${outPath}`));
  });
