#!/usr/bin/env node
import { Command } from 'commander';
import { challengesCmd } from './commands/challenges.js';
import { solveCmd } from './commands/solve.js';
import { submitCmd } from './commands/submit.js';
import { disputeCmd } from './commands/dispute.js';
import { queryCmd } from './commands/query.js';
import { stakeCmd } from './commands/stake.js';
import { validateCmd } from './commands/validate.js';

const program = new Command();

program
  .name('skr')
  .description('SkillRoot command-line interface')
  .version('0.1.0');

program.addCommand(challengesCmd);
program.addCommand(solveCmd);
program.addCommand(submitCmd);
program.addCommand(disputeCmd);
program.addCommand(queryCmd);
program.addCommand(stakeCmd);
program.addCommand(validateCmd);

program.parseAsync(process.argv).catch((e) => {
  console.error(e);
  process.exit(1);
});
