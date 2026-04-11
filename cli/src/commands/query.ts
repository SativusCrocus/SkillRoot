import { Command } from 'commander';
import kleur from 'kleur';
import { formatEther, isAddress, type Address } from 'viem';
import { loadConfig, publicClient } from '../config.js';
import { queryGatewayAbi } from '../abis.js';

const DOMAINS = ['ALGO', 'FORMAL_VER', 'APPLIED_MATH', 'SEC_CODE'];

export const queryCmd = new Command('query')
  .description('read decayed attestation scores for an address')
  .argument('<address>', 'address to query')
  .action(async (addr: string) => {
    if (!isAddress(addr)) throw new Error(`invalid address: ${addr}`);
    const cfg = loadConfig();
    const client = publicClient(cfg);
    const scores = (await client.readContract({
      address: cfg.contracts.gateway,
      abi: queryGatewayAbi,
      functionName: 'verify',
      args: [addr as Address],
    })) as readonly bigint[];

    console.log(kleur.bold(`scores for ${addr}:`));
    scores.forEach((s, i) => {
      const label = DOMAINS[i].padEnd(12);
      const val = s === 0n ? kleur.gray('—') : kleur.green(formatEther(s));
      console.log(`  ${label} ${val}`);
    });
  });
