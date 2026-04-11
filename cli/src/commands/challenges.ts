import { Command } from 'commander';
import kleur from 'kleur';
import { loadConfig, publicClient } from '../config.js';
import { challengeRegistryAbi } from '../abis.js';

const DOMAINS = ['ALGO', 'FORMAL_VER', 'APPLIED_MATH', 'SEC_CODE'];
const STATUS = ['PENDING', 'ACTIVE', 'DEPRECATED', 'REJECTED'];

export const challengesCmd = new Command('challenges')
  .description('list registered challenges')
  .action(async () => {
    const cfg = loadConfig();
    const client = publicClient(cfg);

    const next = await client.readContract({
      address: cfg.contracts.registry,
      abi: challengeRegistryAbi,
      functionName: 'nextChallengeId',
    });
    console.log(kleur.gray(`nextChallengeId: ${next}`));

    for (let id = 1n; id < (next as bigint); id++) {
      const ch = await client.readContract({
        address: cfg.contracts.registry,
        abi: challengeRegistryAbi,
        functionName: 'getChallenge',
        args: [id],
      });
      const statusColor = (ch.status === 1) ? kleur.green : kleur.yellow;
      console.log(
        kleur.bold(`#${ch.id}`),
        statusColor(STATUS[ch.status]),
        kleur.cyan(DOMAINS[ch.domain]),
        kleur.gray(`verifier=${ch.verifier}`)
      );
    }
  });
