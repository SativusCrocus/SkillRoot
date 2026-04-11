import { Command } from 'commander';
import kleur from 'kleur';
import ora from 'ora';
import { parseEther, formatEther } from 'viem';
import { loadConfig, publicClient, walletClient } from '../config.js';
import { skrTokenAbi, stakingVaultAbi } from '../abis.js';

export const stakeCmd = new Command('stake')
  .description('bond SKR as a validator')
  .argument('<amount>', 'amount in SKR (e.g. 5000)')
  .action(async (amountArg: string) => {
    const cfg = loadConfig();
    const pub = publicClient(cfg);
    const wallet = walletClient(cfg);
    const amount = parseEther(amountArg);

    const bal = (await pub.readContract({
      address: cfg.contracts.token,
      abi: skrTokenAbi,
      functionName: 'balanceOf',
      args: [wallet.account.address],
    })) as bigint;
    console.log(kleur.gray(`balance: ${formatEther(bal)} SKR`));

    if (bal < amount) throw new Error(`insufficient balance (need ${formatEther(amount)})`);

    const spin1 = ora('approving...').start();
    const approveHash = await wallet.writeContract({
      address: cfg.contracts.token,
      abi: skrTokenAbi,
      functionName: 'approve',
      args: [cfg.contracts.vault, amount],
    });
    await pub.waitForTransactionReceipt({ hash: approveHash });
    spin1.succeed(`approved ${approveHash}`);

    const spin2 = ora('bonding...').start();
    const bondHash = await wallet.writeContract({
      address: cfg.contracts.vault,
      abi: stakingVaultAbi,
      functionName: 'bond',
      args: [amount],
    });
    const r = await pub.waitForTransactionReceipt({ hash: bondHash });
    spin2.succeed(`bonded in block ${r.blockNumber}`);

    const stakeNow = (await pub.readContract({
      address: cfg.contracts.vault,
      abi: stakingVaultAbi,
      functionName: 'stakeOf',
      args: [wallet.account.address],
    })) as bigint;
    console.log(kleur.green(`stake: ${formatEther(stakeNow)} SKR`));
  });
