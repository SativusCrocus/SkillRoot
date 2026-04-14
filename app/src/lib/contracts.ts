import type { Address } from 'viem';

const ZERO: Address = '0x0000000000000000000000000000000000000000';

/* NOTE: Next.js only inlines `process.env.NEXT_PUBLIC_*` when accessed as a
   static property. Dynamic lookups like `process.env[key]` are NOT replaced
   by webpack's DefinePlugin and become `undefined` in the browser bundle,
   which is why every contract rendered as "not deployed". Keep these as
   literal static accesses. */
function addr(v: string | undefined): Address {
  return v && v.startsWith('0x') ? (v as Address) : ZERO;
}

export const contracts = {
  token:             addr(process.env.NEXT_PUBLIC_SKR_TOKEN),
  vault:             addr(process.env.NEXT_PUBLIC_STAKING_VAULT),
  registry:          addr(process.env.NEXT_PUBLIC_CHALLENGE_REGISTRY),
  engine:            addr(process.env.NEXT_PUBLIC_ATTESTATION_ENGINE),
  gateway:           addr(process.env.NEXT_PUBLIC_QUERY_GATEWAY),
  governance:        addr(process.env.NEXT_PUBLIC_GOVERNANCE),
  sortition:         addr(process.env.NEXT_PUBLIC_SORTITION),
  store:             addr(process.env.NEXT_PUBLIC_ATTESTATION_STORE),
  mathVerifier:      addr(process.env.NEXT_PUBLIC_MATH_VERIFIER),
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
