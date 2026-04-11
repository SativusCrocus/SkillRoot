// Minimal ABIs for CLI. Kept in sync with app/src/lib/abis.ts
// but also includes a few extra methods (events, finalize, etc.)

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
  {
    type: 'function',
    name: 'drawCommittee',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'claimId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'vote',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'claimId', type: 'uint256' },
      { name: 'yes', type: 'bool' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'finalize',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'claimId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'isMember',
    stateMutability: 'view',
    inputs: [
      { name: 'claimId', type: 'uint256' },
      { name: 'validator', type: 'address' },
    ],
    outputs: [{ type: 'bool' }],
  },
  {
    type: 'function',
    name: 'getClaim',
    stateMutability: 'view',
    inputs: [{ name: 'claimId', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'id', type: 'uint256' },
          { name: 'challengeId', type: 'uint256' },
          { name: 'claimant', type: 'address' },
          { name: 'submissionBlock', type: 'uint64' },
          { name: 'voteDeadline', type: 'uint64' },
          { name: 'artifactCID', type: 'bytes32' },
          { name: 'status', type: 'uint8' },
          { name: 'yesVotes', type: 'uint8' },
          { name: 'noVotes', type: 'uint8' },
        ],
      },
    ],
  },
  {
    type: 'event',
    name: 'ClaimSubmitted',
    inputs: [
      { name: 'claimId', type: 'uint256', indexed: true },
      { name: 'challengeId', type: 'uint256', indexed: true },
      { name: 'claimant', type: 'address', indexed: true },
      { name: 'submissionBlock', type: 'uint64', indexed: false },
      { name: 'artifactCID', type: 'bytes32', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'CommitteeDrawn',
    inputs: [
      { name: 'claimId', type: 'uint256', indexed: true },
      { name: 'committee', type: 'address[]', indexed: false },
      { name: 'voteDeadline', type: 'uint64', indexed: false },
    ],
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
