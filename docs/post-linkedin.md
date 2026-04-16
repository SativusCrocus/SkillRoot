# LinkedIn Post — SkillRoot First Attestation

I just submitted the first zero-knowledge proof on my protocol. It took a few weeks of solo building to get here, and I want to share what I learned along the way.

The project is called SkillRoot. The premise is simple: professional credentials are broken. LinkedIn endorsements are traded as favors. GitHub activity measures output volume, not understanding. Certificates prove attendance. None of these things prove you can actually do what you claim. So I built something that does.

SkillRoot uses zero-knowledge proofs to let someone demonstrate competence without revealing private information. The first challenge is a modular exponentiation problem — basic number theory. The prover generates a cryptographic proof that they know the solution, and a smart contract verifies it on-chain. The math checks out, but the contract never sees the answer itself. That's the entire point of ZK.

I built this alone, with heavy AI assistance. Claude helped me write circuits in Circom, debug Solidity contracts, wire up viem for the frontend, and script the deployment pipeline. The honest version: I would not have shipped this in a few weeks without it. The AI didn't replace the architecture decisions or the debugging judgment calls, but it eliminated hundreds of hours of boilerplate and reference lookups. That's a real force multiplier for solo builders.

The hardest bug was invisible. My frontend ABI declared 8 return fields for a contract function that actually returns 9. viem, the Ethereum library I use, decoded the response silently — no error, no warning, just undefined values. The challenge page went completely blank and nothing in the logs explained why. I found it by calling the contract directly from the terminal with cast and counting the return data by hand. One missing struct field, and the entire UI broke without a trace. That's the kind of thing that makes you a better engineer.

The system is live on Base Sepolia right now. Block 40292380, transaction 0xb6b7d1bd. A real Groth16 proof, verified on-chain by a Solidity verifier contract. The claim is pending — it auto-finalizes after a 48-hour rejection window. No committee, no governance vote. Just cryptographic verification and an economic bond.

What's next: I'm pivoting the same ZK primitive toward build attestations. Prove you built something real in a given timeframe — useful for hackathons, AI-assisted development portfolios, and anyone who wants to show verified work rather than a polished resume. The protocol doesn't care who you are. It cares what you can prove.

If you're interested in ZK, on-chain credentials, or building in public as a solo dev, I'll be sharing the technical details as I go. The repo is public. The contracts are deployed. The first proof is on-chain.

Follow along if you want to see where this goes.
