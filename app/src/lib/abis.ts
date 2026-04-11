// Minimal hand-written ABIs for the frontend surface. The full ABIs
// live in contracts/out/ but we only need a few functions per contract
// to keep the bundle small.

export const skrTokenAbi = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'a', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    outputs: [{ type: 'bool' }],
  },
  {
    type: 'function',
    name: 'allowance',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ type: 'uint256' }],
  },
] as const;

export const stakingVaultAbi = [
  {
    type: 'function',
    name: 'stakeOf',
    stateMutability: 'view',
    inputs: [{ name: 'v', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'bond',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'requestUnbond',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'withdraw',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    type: 'function',
    name: 'validatorCount',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
] as const;

export const challengeRegistryAbi = [
  {
    type: 'function',
    name: 'nextChallengeId',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'getChallenge',
    stateMutability: 'view',
    inputs: [{ name: 'id', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'id', type: 'uint256' },
          { name: 'proposer', type: 'address' },
          { name: 'domain', type: 'uint8' },
          { name: 'verifier', type: 'address' },
          { name: 'specCID', type: 'bytes32' },
          { name: 'circuitHash', type: 'bytes32' },
          { name: 'signalWeight', type: 'uint256' },
          { name: 'status', type: 'uint8' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'isActive',
    stateMutability: 'view',
    inputs: [{ name: 'id', type: 'uint256' }],
    outputs: [{ type: 'bool' }],
  },
] as const;

export const attestationEngineAbi = [
  {
    type: 'function',
    name: 'submitClaim',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'challengeId', type: 'uint256' },
      { name: 'a', type: 'uint256[2]' },
      { name: 'b', type: 'uint256[2][2]' },
      { name: 'c', type: 'uint256[2]' },
      { name: 'circuitSignals', type: 'uint256[]' },
      { name: 'artifactCID', type: 'bytes32' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'bindingHashOf',
    stateMutability: 'pure',
    inputs: [
      { name: 'claimant', type: 'address' },
      { name: 'challengeId', type: 'uint256' },
    ],
    outputs: [{ type: 'uint256' }],
  },
] as const;

export const queryGatewayAbi = [
  {
    type: 'function',
    name: 'verify',
    stateMutability: 'view',
    inputs: [{ name: 'claimant', type: 'address' }],
    outputs: [{ type: 'uint256[4]' }],
  },
] as const;
