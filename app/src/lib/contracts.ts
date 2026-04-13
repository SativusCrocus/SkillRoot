import type { Address } from 'viem';

function envAddr(key: string): Address {
  const v = process.env[key];
  if (!v || !v.startsWith('0x')) {
    return '0x0000000000000000000000000000000000000000';
  }
  return v as Address;
}

export const contracts = {
  token:             envAddr('NEXT_PUBLIC_SKR_TOKEN'),
  vault:             envAddr('NEXT_PUBLIC_STAKING_VAULT'),
  registry:          envAddr('NEXT_PUBLIC_CHALLENGE_REGISTRY'),
  engine:            envAddr('NEXT_PUBLIC_ATTESTATION_ENGINE'),
  gateway:           envAddr('NEXT_PUBLIC_QUERY_GATEWAY'),
  governance:        envAddr('NEXT_PUBLIC_GOVERNANCE'),
  sortition:         envAddr('NEXT_PUBLIC_SORTITION'),
  store:             envAddr('NEXT_PUBLIC_ATTESTATION_STORE'),
  mathVerifier:      envAddr('NEXT_PUBLIC_MATH_VERIFIER'),
} as const;

export const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID || '84532');
export const BASESCAN_URL = 'https://sepolia.basescan.org';

export const allContracts: { name: string; key: keyof typeof contracts }[] = [
  { name: 'SKRToken',            key: 'token' },
  { name: 'Governance',          key: 'governance' },
  { name: 'StakingVault',        key: 'vault' },
  { name: 'ChallengeRegistry',   key: 'registry' },
  { name: 'Sortition',           key: 'sortition' },
  { name: 'AttestationStore',    key: 'store' },
  { name: 'AttestationEngine',   key: 'engine' },
  { name: 'QueryGateway',        key: 'gateway' },
  { name: 'MathVerifierAdapter', key: 'mathVerifier' },
];
