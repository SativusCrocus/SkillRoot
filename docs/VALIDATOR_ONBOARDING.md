# SkillRoot v0 — Validator Onboarding (Base Sepolia)

You are joining as one of the first 5 validators on SkillRoot's live testnet. Follow every step exactly.

**Chain:** Base Sepolia (84532)
**Minimum stake:** 5,000 SKR
**Vote window:** 24 hours per claim
**Slashing:** 1% liveness (no-show), 5% equivocation (wrong vote)

---

## Prerequisites

| Tool | Install |
|------|---------|
| Node.js >= 20 | `curl -fsSL https://fnm.vercel.app/install \| bash && fnm install 20` |
| pnpm >= 9 | `npm i -g pnpm@9` |
| Foundry (cast) | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| Git | system default |

---

## Step 1 — Generate your validator key

```bash
# Generate a fresh key (NEVER reuse a mainnet key)
cast wallet new

# Output:
#   Address:     0xYOUR_ADDRESS
#   Private key: 0xYOUR_PRIVATE_KEY

# Save the private key — you'll need it for every step
export PRIVATE_KEY=0xYOUR_PRIVATE_KEY
export VALIDATOR_ADDR=$(cast wallet address --private-key $PRIVATE_KEY)
echo "validator: $VALIDATOR_ADDR"
```

Send your `$VALIDATOR_ADDR` to the SkillRoot team via the Discord `#validators` channel. The team will fund you with:
- **0.005 ETH** (gas on Base Sepolia)
- **5,000 SKR** (staking tokens)

Verify you received both:

```bash
export RPC=https://sepolia.base.org

# Check ETH balance
cast balance $VALIDATOR_ADDR --rpc-url $RPC

# Check SKR balance
cast call 0xbd8Fe0fE752A1B0135DDdD99357De060e2C92392 \
  "balanceOf(address)(uint256)" $VALIDATOR_ADDR --rpc-url $RPC
# Should show 5000000000000000000000 (5000 * 1e18)
```

---

## Step 2 — Clone repo and build the CLI

```bash
git clone https://github.com/SativusCrocus/SkillRoot.git
cd SkillRoot
pnpm install
pnpm -C cli build
```

Set up the CLI config:

```bash
mkdir -p ~/.skr/deployments

cat > ~/.skr/deployments/base-sepolia.json << 'EOF'
{
  "chainId": 84532,
  "rpcUrl": "https://sepolia.base.org",
  "contracts": {
    "token":      "0xbd8Fe0fE752A1B0135DDdD99357De060e2C92392",
    "vault":      "0x0aD5A748965895709a0D68E3e669dCB97a6B43C1",
    "registry":   "0x7585959e8f0B5C17D40ff0Cd2564417E50135c78",
    "engine":     "0x86b5A121568829981593e5Be2D597dFb99DC7E49",
    "gateway":    "0xFb648E415BAbBbFBf882Cc64a02cBc5DAFAB0D14",
    "governance": "0x0Bd5D8Cb003EE175D19B29F8B50E99d5959eABDE"
  }
}
EOF
```

Verify the CLI loads:

```bash
PRIVATE_KEY=$PRIVATE_KEY node cli/dist/bin.js challenges
# Should list challenge #1 (APPLIED_MATH, active)
```

---

## Step 3 — Stake 5,000 SKR

```bash
PRIVATE_KEY=$PRIVATE_KEY node cli/dist/bin.js stake 5000
```

Expected output:

```
balance: 5000.0 SKR
✔ approved 0x...
✔ bonded in block 12345678
stake: 5000.0 SKR
```

Confirm on-chain:

```bash
cast call 0x0aD5A748965895709a0D68E3e669dCB97a6B43C1 \
  "stakeOf(address)(uint256)" $VALIDATOR_ADDR --rpc-url $RPC
# 5000000000000000000000
```

---

## Step 4 — Run the validator daemon

**Terminal session (tmux/screen recommended):**

```bash
PRIVATE_KEY=$PRIVATE_KEY node cli/dist/bin.js validate
```

Expected output:

```
skr validate
  validator    = 0xYOUR_ADDRESS
  engine       = 0x86b5A121568829981593e5Be2D597dFb99DC7E49
  vkey         = ./circuits/math/build/verification_key.json
```

The daemon polls every 4 seconds for `CommitteeDrawn` events. When you're drawn onto a committee, it votes automatically.

**Production setup (systemd):**

```bash
sudo tee /etc/systemd/system/skr-validator.service << EOF
[Unit]
Description=SkillRoot Validator Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/SkillRoot
Environment=PRIVATE_KEY=$PRIVATE_KEY
ExecStart=$(which node) cli/dist/bin.js validate
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now skr-validator
sudo journalctl -u skr-validator -f
```

---

## Step 5 — Verify and claim rewards

**Check your vote history:**

When drawn to a committee, the daemon logs:

```
[claim 1] in committee, verifying...
[claim 1] voted YES (tx 0x...)
```

**Check your stake is intact (no slashing):**

```bash
cast call 0x0aD5A748965895709a0D68E3e669dCB97a6B43C1 \
  "stakeOf(address)(uint256)" $VALIDATOR_ADDR --rpc-url $RPC
```

**View the attestation you helped validate:**

```bash
PRIVATE_KEY=$PRIVATE_KEY node cli/dist/bin.js query 0x709a38C670f15E0E1763A7F42F616526F4e62118
# Shows decayed scores for the founder attestation
```

**Unbonding (14-day delay):**

```bash
# Only do this when you want to stop validating
cast send 0x0aD5A748965895709a0D68E3e669dCB97a6B43C1 \
  "requestUnbond(uint256)" "5000000000000000000000" \
  --rpc-url $RPC --private-key $PRIVATE_KEY

# After 14 days:
cast send 0x0aD5A748965895709a0D68E3e669dCB97a6B43C1 \
  "withdraw()" \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

---

## Contract Addresses (Base Sepolia)

| Contract | Address |
|----------|---------|
| SKRToken | `0xbd8Fe0fE752A1B0135DDdD99357De060e2C92392` |
| StakingVault | `0x0aD5A748965895709a0D68E3e669dCB97a6B43C1` |
| ChallengeRegistry | `0x7585959e8f0B5C17D40ff0Cd2564417E50135c78` |
| AttestationEngine | `0x86b5A121568829981593e5Be2D597dFb99DC7E49` |
| QueryGateway | `0xFb648E415BAbBbFBf882Cc64a02cBc5DAFAB0D14` |
| Governance | `0x0Bd5D8Cb003EE175D19B29F8B50E99d5959eABDE` |
| MathGroth16Verifier | `0x39041f0DB8E566c72D407d81F67B931560B30619` |
| MathVerifierAdapter | `0x0984eC92acf7AA83454c26862ef25856Df862Edd` |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `insufficient balance` on stake | Team hasn't funded you yet — ping `#validators` |
| `BelowMinStake` revert | Stake must be >= 1,000 SKR in a single `bond()` call |
| Daemon shows no committee events | No claims submitted yet — this is normal, keep running |
| `vote failed: AlreadyVoted` | Daemon restarted and re-processed a claim — harmless, dedup handles it |
| `vote failed: VoteClosed` | Claim expired before you voted — check daemon uptime |
| Stake decreased unexpectedly | You were slashed: 1% for missing a vote, 5% for voting against consensus |
