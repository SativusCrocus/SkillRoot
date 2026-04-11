import type { Address } from 'viem';

function envAddr(key: string): Address {
  const v = process.env[key];
  if (!v || !v.startsWith('0x')) {
    // Return a zero address during builds before deployment
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
} as const;
