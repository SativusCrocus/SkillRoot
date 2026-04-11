# @skillroot/cli

SkillRoot command-line interface. Single binary, all commands.

## Install

```
pnpm install
pnpm build
# optional: link globally
pnpm link --global
```

## Commands

```
skr challenges                              # list registered challenges
skr solve 1 --base 2 --exp 20 --mod 97      # generate a math proof
skr submit ./proofs/calldata-1.json         # submit proof to engine
skr query 0x...                             # read decayed scores
skr stake 5000                              # bond 5000 SKR as a validator
skr validate                                # run validator daemon
```

## Configuration

The CLI reads:

- `PRIVATE_KEY` env var — signing key
- `SKR_CHAIN_ID` env var — override target chain
- `SKR_RPC_URL` env var — override RPC endpoint
- `SKR_DEPLOYMENT` env var — path to deployment JSON
  (default: `~/.skr/deployments/base-sepolia.json`)

`scripts/deploy-sepolia.sh` writes the JSON automatically after a fresh deploy.
