# SkillRoot Launch Thread

## 1/7

Built a ZK attestation protocol solo over a few weeks. Just submitted the first real proof on-chain. Here's exactly how it works, from circuit to transaction.

## 2/7

LinkedIn skills are self-declared — anyone clicks "endorse" with zero verification. GitHub stars measure popularity, not competence. Certificates prove you sat through a course, not that you can build. All three are trivially gameable. None prove you actually know something.

## 3/7

I wrote a Circom circuit: prove you know an exponent e where base^e mod m = result. snarkjs generates a Groth16 proof. A Solidity verifier checks it on-chain. First proof: 3^7 mod 13 = 3. The chain confirms the answer is correct. It never sees the exponent.

## 4/7

Cold-start problem: protocol needs stakers to enforce the 48h rejection window. At launch there are none. genesisActivate() is one-shot, deployer-only. Activates the first challenge, then sets genesisDeployer = address(0). Can never fire twice. One key, one use.

## 5/7

Bug that nearly killed the frontend: getChallenge returns 9 fields, my ABI declared 8. Missing rejectionDeadline. viem decoded silently — no error, just undefined. Page blank. Found it with cast call, counting return words. Lesson: diff your ABI against the deployed contract.

## 6/7

Block 40292380, Base Sepolia. Groth16 proof verified on-chain by MathVerifier. 100 SKR bond locked. Claim status: PENDING — auto-finalizes after the rejection window closes. No committee, no vote. Just math.

tx: 0xb6b7d1bd60871bfccd1b3a4f4d0fcb24f7af1beaf2903d0f3391f68c481835a9

## 7/7

Next: same ZK primitive, new use case. Prove you built something real in N hours — for hackathons, vibe coders, AI-assisted dev. Verifiable build attestations, not self-reported resumes. If that sounds useful, follow along. #zkproofs #ethereum
