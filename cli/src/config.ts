import { createPublicClient, createWalletClient, http, type Address, type Hex } from 'viem';
import { baseSepolia, base, foundry } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';

const CHAIN_BY_ID: Record<number, typeof baseSepolia> = {
  [baseSepolia.id]: baseSepolia,
  [base.id]: base,
  [foundry.id]: foundry,
};

export interface Config {
  chainId: number;
  rpcUrl: string;
  contracts: {
    token: Address;
    vault: Address;
    registry: Address;
    engine: Address;
    gateway: Address;
    store?: Address;
    fraudVerifier?: Address;
    fraudVerifierAdapter?: Address;
  };
}

export function loadConfig(): Config {
  // 1. env overrides
  const envChain = process.env.SKR_CHAIN_ID ? Number(process.env.SKR_CHAIN_ID) : undefined;
  const envRpc = process.env.SKR_RPC_URL;

  // 2. deployments file (written by scripts/deploy-sepolia.sh)
  const deploymentPath =
    process.env.SKR_DEPLOYMENT ||
    path.resolve(os.homedir(), '.skr/deployments/base-sepolia.json');

  let fromFile: Partial<Config> = {};
  if (fs.existsSync(deploymentPath)) {
    const parsed = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));
    fromFile = {
      chainId: parsed.chainId,
      rpcUrl: parsed.rpcUrl,
      contracts: parsed.contracts,
    };
  }

  const chainId = envChain ?? fromFile.chainId ?? baseSepolia.id;
  const rpcUrl = envRpc ?? fromFile.rpcUrl ?? 'http://127.0.0.1:8545';
  const contracts = fromFile.contracts ?? {
    token: '0x0000000000000000000000000000000000000000' as Address,
    vault: '0x0000000000000000000000000000000000000000' as Address,
    registry: '0x0000000000000000000000000000000000000000' as Address,
    engine: '0x0000000000000000000000000000000000000000' as Address,
    gateway: '0x0000000000000000000000000000000000000000' as Address,
  };

  return { chainId, rpcUrl, contracts };
}

export function publicClient(cfg: Config) {
  const chain = CHAIN_BY_ID[cfg.chainId];
  if (!chain) throw new Error(`unsupported chain id ${cfg.chainId}`);
  return createPublicClient({ chain, transport: http(cfg.rpcUrl) });
}

export function walletClient(cfg: Config) {
  const pk = process.env.PRIVATE_KEY;
  if (!pk) throw new Error('PRIVATE_KEY not set in environment');
  const account = privateKeyToAccount(pk as Hex);
  const chain = CHAIN_BY_ID[cfg.chainId];
  if (!chain) throw new Error(`unsupported chain id ${cfg.chainId}`);
  return createWalletClient({ chain, transport: http(cfg.rpcUrl), account });
}
