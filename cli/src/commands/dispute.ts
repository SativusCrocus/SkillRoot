import { Command } from 'commander';
import kleur from 'kleur';
import ora from 'ora';
import * as fs from 'node:fs';
import { loadConfig, publicClient, walletClient } from '../config.js';

/*
 * Minimal inline ABI for AttestationEngine.submitFraudProof. Kept local to
 * this file so adding fraud-proof support does not require editing the
 * shared abis.ts (which is still used by the legacy submit command).
 */
const fraudEngineAbi = [
  {
    type: 'function',
    name: 'submitFraudProof',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'claimId', type: 'uint256' },
      { name: 'a', type: 'uint256[2]' },
      { name: 'b', type: 'uint256[2][2]' },
      { name: 'c', type: 'uint256[2]' },
      { name: 'fraudSignals', type: 'uint256[]' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'getClaim',
    stateMutability: 'view',
    inputs: [{ name: 'claimId', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'id', type: 'uint256' },
          { name: 'challengeId', type: 'uint256' },
          { name: 'claimant', type: 'address' },
          { name: 'submittedAt', type: 'uint64' },
          { name: 'challengeDeadline', type: 'uint64' },
          { name: 'bond', type: 'uint256' },
          { name: 'artifactCID', type: 'bytes32' },
          { name: 'status', type: 'uint8' },
        ],
      },
    ],
  },
] as const;

interface Calldata {
  a: [string, string];
  b: [[string, string], [string, string]];
  c: [string, string];
  pubSignals: string[];
  circuitSignals: string[];
}

export const disputeCmd = new Command('dispute')
  .description('submit a fraud proof against a PENDING claim (v0.2.0-no-vote)')
  .argument('<claimId>', 'claim id to dispute')
  .argument(
    '<calldataPath>',
    'path to fraud calldata.json emitted by `snarkjs groth16 prove` against circuits/fraud (use gen-fraud-input.ts for the witness)'
  )
  .action(async (claimIdArg: string, calldataPath: string) => {
    const cfg = loadConfig();
    const pub = publicClient(cfg);
    const wallet = walletClient(cfg);

    const cd: Calldata = JSON.parse(fs.readFileSync(calldataPath, 'utf8'));
    const claimId = BigInt(claimIdArg);

    // Preflight: inspect the claim. PENDING = 0; anything else is unrecoverable.
    const claim = (await pub.readContract({
      address: cfg.contracts.engine,
      abi: fraudEngineAbi,
      functionName: 'getClaim',
      args: [claimId],
    })) as {
      id: bigint;
      challengeId: bigint;
      claimant: `0x${string}`;
      submittedAt: bigint;
      challengeDeadline: bigint;
      bond: bigint;
      artifactCID: `0x${string}`;
      status: number;
    };

    if (claim.id === 0n) {
      console.error(kleur.red(`claim ${claimId} does not exist`));
      process.exit(1);
    }
    if (claim.status !== 0) {
      const label = claim.status === 1 ? 'FINALIZED_ACCEPT' : 'FINALIZED_REJECT';
      console.error(kleur.red(`claim ${claimId} is already ${label} — cannot dispute`));
      process.exit(1);
    }
    const nowSec = BigInt(Math.floor(Date.now() / 1000));
    if (nowSec > claim.challengeDeadline) {
      console.error(
        kleur.red(
          `challenge window closed at ${new Date(
            Number(claim.challengeDeadline) * 1000
          ).toISOString()} — run finalizeClaim instead`
        )
      );
      process.exit(1);
    }

    console.log(kleur.dim(`claimant       ${claim.claimant}`));
    console.log(kleur.dim(`challengeId    ${claim.challengeId}`));
    console.log(
      kleur.dim(
        `deadline       ${new Date(
          Number(claim.challengeDeadline) * 1000
        ).toISOString()}`
      )
    );
    console.log(kleur.dim(`bond at stake  ${claim.bond}`));

    const spin = ora(`submitting fraud proof for claim ${claimId}...`).start();
    const hash = await wallet.writeContract({
      address: cfg.contracts.engine,
      abi: fraudEngineAbi,
      functionName: 'submitFraudProof',
      args: [
        claimId,
        [BigInt(cd.a[0]), BigInt(cd.a[1])],
        [
          [BigInt(cd.b[0][0]), BigInt(cd.b[0][1])],
          [BigInt(cd.b[1][0]), BigInt(cd.b[1][1])],
        ],
        [BigInt(cd.c[0]), BigInt(cd.c[1])],
        cd.circuitSignals.map((s) => BigInt(s)),
      ],
    });
    spin.text = `tx ${hash} — waiting for confirmation...`;
    const receipt = await pub.waitForTransactionReceipt({ hash });
    spin.succeed(`fraud proof confirmed in block ${receipt.blockNumber}`);
    console.log(
      kleur.green(
        `disputed. claim ${claimId} → FINALIZED_REJECT. bond split: half to you, half burned. gas used: ${receipt.gasUsed}`
      )
    );
  });
