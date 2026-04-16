# First Attestation — Challenge #1 (APPLIED_MATH)

## Submission Details

| Field | Value |
|-------|-------|
| **Date** | 2026-04-16 ~15:17 UTC |
| **Challenge ID** | 1 |
| **Domain** | APPLIED_MATH — Modular Exponentiation |
| **Claim ID** | 1 |
| **Submitter** | `0x709a38C670f15E0E1763A7F42F616526F4e62118` |
| **Status** | PENDING (0) — auto-finalizes after rejection deadline |

## Circuit Inputs

| Parameter | Value |
|-----------|-------|
| base | 3 |
| exponent | 7 |
| modulus | 13 |
| result | 3 (since 3^7 mod 13 = 2187 mod 13 = 3) |

## On-Chain Proof

- **Transaction**: [0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9](https://sepolia.basescan.org/tx/0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9)
- **Block**: 40292380
- **Gas Used**: 435,451
- **Contract**: AttestationEngine at `0xF2541F68f47f5aB978979B5Ab766f08750d915e8`
- **Network**: Base Sepolia (chain ID 84532)
- **Bond**: 100 SKR (locked until finalization)

## Calldata

Proof artifacts stored at: `proofs/calldata-1.json`

## Pipeline

1. `skr solve 1 --base 3 --exp 7 --mod 13` — generated Groth16 proof via snarkjs
2. `cast send` — approved 1000 SKR token spend for AttestationEngine
3. `skr submit proofs/calldata-1.json --challenge 1` — submitted claim on-chain
4. Proof verified on-chain by MathVerifier, claim registered as PENDING

This confirms the full end-to-end pipeline works: circuit witness generation, Groth16 proving, on-chain verification, and claim registration on Base Sepolia.
