#!/usr/bin/env node
import { Command } from 'commander';
import { challengesCmd } from './commands/challenges.js';
import { solveCmd } from './commands/solve.js';
import { submitCmd } from './commands/submit.js';
import { disputeCmd } from './commands/dispute.js';
import { queryCmd } from './commands/query.js';
import { stakeCmd } from './commands/stake.js';

const program = new Command();

program
  .name('skr')
  .description('SkillRoot command-line interface (v0.2.0-no-vote)')
  .version('0.2.0');

program.addCommand(challengesCmd);
program.addCommand(solveCmd);
program.addCommand(submitCmd);
program.addCommand(disputeCmd);
program.addCommand(queryCmd);
program.addCommand(stakeCmd);

program.parseAsync(process.argv).catch((e) => {
  console.error(e);
  process.exit(1);
});
