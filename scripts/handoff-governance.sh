#!/usr/bin/env bash
#
# handoff-governance.sh — Week 8 handover: rotate the genesis governance
# role from the deployer EOA to the final governance owner.
#
# Rotation options:
#   1. handover to Governance contract (default)
#   2. handover to a 5-signer Gnosis Safe multi-sig (set OWNER=<safe address>)
#   3. handover to a Governance contract that is THEN owned by a Safe
#      (set OWNER to the Governance contract and then, via a governance
#      proposal, transferGovernance to the Safe — a two-step rotation)
#
# What this script does:
#   - Moves the remaining treasury SKR from deployer → Governance contract
#     (unless --skip-treasury is passed)
#   - Calls transferGovernance on all 5 subsystem contracts
#   - Writes a receipt JSON at deployments/handoff-<timestamp>.json
#
# ⚠️  This is a one-way operation. The deployer loses governance rights
# immediately. Dry-run first with DRY_RUN=1.
#
# Environment:
#   PRIVATE_KEY   - deployer key (must currently hold governance on all 5)
#   RPC_URL       - target RPC (Base Sepolia)
#   DEPLOYMENT    - optional path (default deployments/base-sepolia.json)
#   OWNER         - optional override for the new governance owner
#                   (default: the Governance contract address from deployment)
#   SKIP_TREASURY - set to 1 to leave treasury with deployer
#   DRY_RUN       - set to 1 to print planned txns without broadcasting

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

: "${PRIVATE_KEY:?set PRIVATE_KEY in env}"
: "${RPC_URL:?set RPC_URL in env}"

export PATH="$HOME/.foundry/bin:$PATH"

DEPLOYMENT="${DEPLOYMENT:-$ROOT/deployments/base-sepolia.json}"

if [ ! -f "$DEPLOYMENT" ]; then
  echo "[err] no deployment JSON at $DEPLOYMENT" >&2
  exit 1
fi

parse() { python3 -c "import json; print(json.load(open('$DEPLOYMENT'))['contracts']['$1'])"; }
TOKEN=$(parse SKRToken)
GOV=$(parse Governance)
VAULT=$(parse StakingVault)
REGISTRY=$(parse ChallengeRegistry)
STORE=$(parse AttestationStore)
ENGINE=$(parse AttestationEngine)

NEW_OWNER="${OWNER:-$GOV}"
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")

# --- sanity checks -----------------------------------------------------------
check_governance() {
  local contract="$1"
  local label="$2"
  local current
  current=$(cast call "$contract" "governance()(address)" --rpc-url "$RPC_URL" | awk '{print $1}')
  # Use python for case-insensitive compare (bash 3.2 on macOS has no ${var,,})
  if ! python3 -c "import sys; sys.exit(0 if '$current'.lower() == '$DEPLOYER'.lower() else 1)"; then
    echo "[err] $label: current governance = $current, expected deployer $DEPLOYER" >&2
    return 1
  fi
  echo "[ok] $label governance held by deployer"
}

echo "[..] verifying deployer holds all governance roles"
check_governance "$TOKEN"    "SKRToken"
check_governance "$VAULT"    "StakingVault"
check_governance "$REGISTRY" "ChallengeRegistry"
check_governance "$STORE"    "AttestationStore"
check_governance "$ENGINE"   "AttestationEngine"

echo
echo "[..] handoff plan"
echo "     from          : $DEPLOYER"
echo "     to            : $NEW_OWNER"
if [ "$NEW_OWNER" = "$GOV" ]; then
  echo "     (= Governance contract at $GOV)"
else
  echo "     (= custom owner; Governance contract at $GOV will NOT own subsystems)"
fi
echo "     token         : $TOKEN"
echo "     vault         : $VAULT"
echo "     registry      : $REGISTRY"
echo "     store         : $STORE"
echo "     engine        : $ENGINE"

# --- treasury transfer -------------------------------------------------------
TREASURY_BAL=$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url "$RPC_URL" | awk '{print $1}')
echo "     deployer bal  : $TREASURY_BAL wei"

if [ "${SKIP_TREASURY:-0}" = "1" ]; then
  echo "     (SKIP_TREASURY=1, leaving treasury with deployer)"
else
  if python3 -c "import sys; sys.exit(0 if int('$TREASURY_BAL') == 0 else 1)"; then
    echo "     (deployer holds 0 treasury; nothing to move)"
  else
    echo "     will transfer entire deployer balance → $NEW_OWNER"
  fi
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo
  echo "[dry-run] no transactions broadcast"
  exit 0
fi

# --- execute -----------------------------------------------------------------
echo
echo "[..] transferring governance roles"

transfer_gov() {
  local contract="$1"
  local label="$2"
  printf "     %s → " "$label"
  local tx
  tx=$(cast send "$contract" \
    "transferGovernance(address)" "$NEW_OWNER" \
    --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" \
    --json | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])")
  printf "tx=%s\n" "$tx"
}

# Do treasury BEFORE governance transfer — otherwise the deployer loses
# the ability to move tokens. (Actually: ERC20 transfer doesn't require
# governance role, so order is flexible; but we do treasury first anyway
# for clarity.)
if [ "${SKIP_TREASURY:-0}" != "1" ]; then
  if ! python3 -c "import sys; sys.exit(0 if int('$TREASURY_BAL') == 0 else 1)"; then
    printf "[..] transferring %s wei treasury → %s " "$TREASURY_BAL" "$NEW_OWNER"
    TREASURY_TX=$(cast send "$TOKEN" \
      "transfer(address,uint256)" "$NEW_OWNER" "$TREASURY_BAL" \
      --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" \
      --json | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])")
    printf "tx=%s\n" "$TREASURY_TX"
  fi
fi

transfer_gov "$TOKEN"    "SKRToken        "
transfer_gov "$VAULT"    "StakingVault    "
transfer_gov "$REGISTRY" "ChallengeRegistry"
transfer_gov "$STORE"    "AttestationStore "
transfer_gov "$ENGINE"   "AttestationEngine"

# --- verify ------------------------------------------------------------------
echo
echo "[..] verifying new governance roles"
verify() {
  local contract="$1"
  local label="$2"
  local current
  current=$(cast call "$contract" "governance()(address)" --rpc-url "$RPC_URL" | awk '{print $1}')
  if python3 -c "import sys; sys.exit(0 if '$current'.lower() == '$NEW_OWNER'.lower() else 1)"; then
    echo "[ok]  $label → $current"
  else
    echo "[err] $label → $current (expected $NEW_OWNER)" >&2
    return 1
  fi
}
verify "$TOKEN"    "SKRToken        "
verify "$VAULT"    "StakingVault    "
verify "$REGISTRY" "ChallengeRegistry"
verify "$STORE"    "AttestationStore "
verify "$ENGINE"   "AttestationEngine"

# --- receipt -----------------------------------------------------------------
TS=$(date -u +%Y%m%dT%H%M%SZ)
RECEIPT="$ROOT/deployments/handoff-$TS.json"
cat > "$RECEIPT" <<JSON
{
  "handoffAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "from":  "$DEPLOYER",
  "to":    "$NEW_OWNER",
  "chain": "$(cast chain-id --rpc-url $RPC_URL)",
  "contracts": {
    "SKRToken":          "$TOKEN",
    "StakingVault":      "$VAULT",
    "ChallengeRegistry": "$REGISTRY",
    "AttestationStore":  "$STORE",
    "AttestationEngine": "$ENGINE",
    "Governance":        "$GOV"
  },
  "treasuryMoved": $( [ "${SKIP_TREASURY:-0}" = "1" ] && echo "false" || echo "true" ),
  "notes": "If NEW_OWNER != Governance contract, the Governance contract is now a spectator and cannot execute calls against the subsystems. Restore via the new owner if this was unintended."
}
JSON
echo
echo "[ok] handoff complete"
echo "     receipt → $RECEIPT"
