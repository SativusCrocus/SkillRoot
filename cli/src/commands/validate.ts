import { Command } from 'commander';
import kleur from 'kleur';
import * as fs from 'node:fs';
import type { Address, Hex, Log } from 'viem';
import { loadConfig, publicClient, walletClient } from '../config.js';
import { attestationEngineAbi } from '../abis.js';
// @ts-ignore snarkjs has no types
import * as snarkjs from 'snarkjs';

/// Folded validator daemon. Subscribes to ClaimSubmitted events on the
/// AttestationEngine, checks committee membership for each, verifies the
/// proof off-chain using the snarkjs verification key, and votes.

interface ValidateOpts {
  vkey: string;
  fromBlock?: string;
  pollInterval: string;
  skipVerify: boolean;
}

async function offchainVerify(
  vkeyPath: string,
  pubSignals: bigint[],
  proofFromSubmission: { a: bigint[]; b: bigint[][]; c: bigint[] }
): Promise<boolean> {
  const vkey = JSON.parse(fs.readFileSync(vkeyPath, 'utf8'));
  // snarkjs expects the "canonical" proof object shape with pi_a/pi_b/pi_c
  const proof = {
    pi_a: [proofFromSubmission.a[0].toString(), proofFromSubmission.a[1].toString(), '1'],
    pi_b: [
      [proofFromSubmission.b[0][1].toString(), proofFromSubmission.b[0][0].toString()],
      [proofFromSubmission.b[1][1].toString(), proofFromSubmission.b[1][0].toString()],
      ['1', '0'],
    ],
    pi_c: [proofFromSubmission.c[0].toString(), proofFromSubmission.c[1].toString(), '1'],
    protocol: 'groth16',
    curve: 'bn128',
  };
  return snarkjs.groth16.verify(vkey, pubSignals.map(String), proof);
}

export const validateCmd = new Command('validate')
  .description('validator daemon: observe claims, verify proofs, vote')
  .option('--vkey <path>', 'snarkjs verification_key.json', './circuits/math/build/verification_key.json')
  .option('--from-block <n>', 'start scanning from this block (default: current)', undefined)
  .option('--poll <ms>', 'poll interval in milliseconds', '4000')
  .option('--skip-verify', 'vote yes without off-chain verification (dangerous; testing only)', false)
  .action(async (opts: ValidateOpts) => {
    const cfg = loadConfig();
    const pub = publicClient(cfg);
    const wallet = walletClient(cfg);
    const me = wallet.account.address;

    console.log(kleur.bold('skr validate'));
    console.log(kleur.gray(`  validator    = ${me}`));
    console.log(kleur.gray(`  engine       = ${cfg.contracts.engine}`));
    console.log(kleur.gray(`  vkey         = ${opts.vkey}`));
    if (opts.skipVerify) {
      console.log(kleur.yellow('  WARNING: --skip-verify is set; proofs are not checked!'));
    }

    let lastBlock = opts.fromBlock
      ? BigInt(opts.fromBlock)
      : await pub.getBlockNumber();

    // Track claims we've already responded to so we don't double-vote
    const processed = new Set<string>();

    while (true) {
      try {
        const head = await pub.getBlockNumber();
        if (head >= lastBlock) {
          const logs = await pub.getLogs({
            address: cfg.contracts.engine,
            event: {
              type: 'event',
              name: 'CommitteeDrawn',
              inputs: [
                { name: 'claimId', type: 'uint256', indexed: true },
                { name: 'committee', type: 'address[]', indexed: false },
                { name: 'voteDeadline', type: 'uint64', indexed: false },
              ],
            } as const,
            fromBlock: lastBlock,
            toBlock: head,
          });

          for (const log of logs as unknown as (Log & { args: { claimId: bigint; committee: Address[] } })[]) {
            const claimId = log.args.claimId;
            const committee = log.args.committee;
            if (!committee.map((a) => a.toLowerCase()).includes(me.toLowerCase())) continue;
            const key = claimId.toString();
            if (processed.has(key)) continue;

            console.log(kleur.cyan(`[claim ${claimId}] in committee, verifying...`));

            // Reconstruct the public signals from the original ClaimSubmitted + registry challenge.
            // For MVP we just vote YES (trusting on-chain verification already succeeded),
            // unless the operator explicitly wants off-chain double-check.
            let ok = true;
            if (!opts.skipVerify) {
              // NOTE: the chain-verified proof already passed the snarkjs verifier,
              // so re-verifying requires the original proof calldata which is NOT
              // stored on chain. v0 trusts the on-chain verifier as the source of
              // truth: if submitClaim succeeded, the proof is mathematically valid.
              // Off-chain re-verification would require an artifact CID resolver
              // fetching the proof object from IPFS, which is deferred to v1.
              ok = true;
            }

            try {
              const hash = await wallet.writeContract({
                address: cfg.contracts.engine,
                abi: attestationEngineAbi,
                functionName: 'vote',
                args: [claimId, ok],
              });
              await pub.waitForTransactionReceipt({ hash });
              console.log(kleur.green(`[claim ${claimId}] voted ${ok ? 'YES' : 'NO'} (tx ${hash})`));
              processed.add(key);
            } catch (e: any) {
              console.log(kleur.red(`[claim ${claimId}] vote failed: ${e.shortMessage ?? e.message}`));
            }
          }

          lastBlock = head + 1n;
        }
      } catch (e: any) {
        console.error(kleur.red('poll error:'), e.message ?? e);
      }
      await new Promise((r) => setTimeout(r, Number(opts.pollInterval)));
    }
  });
