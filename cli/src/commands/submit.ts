import { Command } from 'commander';
import kleur from 'kleur';
import ora from 'ora';
import * as fs from 'node:fs';
import { stringToBytes, bytesToHex, type Hex } from 'viem';
import { loadConfig, publicClient, walletClient } from '../config.js';
import { attestationEngineAbi } from '../abis.js';

interface Calldata {
  a: [string, string];
  b: [[string, string], [string, string]];
  c: [string, string];
  pubSignals: string[];
  circuitSignals: string[];
}

export const submitCmd = new Command('submit')
  .description('submit a generated proof to AttestationEngine')
  .argument('<calldataPath>', 'path to calldata.json emitted by `skr solve`')
  .option('--challenge <id>', 'challenge id', '1')
  .option('--cid <cid>', 'IPFS/Arweave artifact CID (optional)', '')
  .action(async (calldataPath: string, opts: any) => {
    const cfg = loadConfig();
    const pub = publicClient(cfg);
    const wallet = walletClient(cfg);

    const raw = fs.readFileSync(calldataPath, 'utf8');
    const cd: Calldata = JSON.parse(raw);
    const challengeId = BigInt(opts.challenge);

    const cidBytes = stringToBytes(opts.cid || '', { size: 32 });
    const cidHex = bytesToHex(cidBytes) as Hex;

    const spin = ora('submitting claim...').start();
    const hash = await wallet.writeContract({
      address: cfg.contracts.engine,
      abi: attestationEngineAbi,
      functionName: 'submitClaim',
      args: [
        challengeId,
        [BigInt(cd.a[0]), BigInt(cd.a[1])],
        [
          [BigInt(cd.b[0][0]), BigInt(cd.b[0][1])],
          [BigInt(cd.b[1][0]), BigInt(cd.b[1][1])],
        ],
        [BigInt(cd.c[0]), BigInt(cd.c[1])],
        cd.circuitSignals.map((s) => BigInt(s)),
        cidHex,
      ],
    });
    spin.text = `tx ${hash} — waiting for confirmation...`;
    const receipt = await pub.waitForTransactionReceipt({ hash });
    spin.succeed(`confirmed in block ${receipt.blockNumber}`);
    console.log(kleur.green(`submitted. gas used: ${receipt.gasUsed}`));
  });
