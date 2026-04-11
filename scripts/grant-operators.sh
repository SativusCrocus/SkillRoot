#!/usr/bin/env bash
#
# grant-operators.sh — transfer the 5x 5,000 SKR bootstrap grants from the
# Governance treasury (or deployer EOA, while it still holds the treasury)
# to the invited external operators.
#
# This script is used during Week 7 of bootstrapping (see
# docs/bootstrapping.md). It expects the deployer to still hold the SKR
# treasury — i.e. Deploy.s.sol was run with SKIP_GOV_TRANSFER=1 and the
# governance handover has not happened yet.
#
# The list of operator addresses is read either from an operators.txt
# file (one 0x… address per line, # comments allowed) or from the
# OPERATORS env var as a comma-separated list.
#
# Environment:
#   PRIVATE_KEY   - deployer key (still holds treasury)
#   RPC_URL       - target RPC (Base Sepolia)
#   DEPLOYMENT    - optional path (default deployments/base-sepolia.json)
#   GRANT_AMOUNT  - SKR per operator (default 5000)
#   OPERATORS     - optional CSV override of recipient addresses
#   OPERATORS_FILE- optional path override (default operators.txt at repo root)
#   DRY_RUN       - set to 1 to print txns without broadcasting

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

: "${PRIVATE_KEY:?set PRIVATE_KEY in env}"
: "${RPC_URL:?set RPC_URL in env}"

# Ensure foundry in PATH
export PATH="$HOME/.foundry/bin:$PATH"

DEPLOYMENT="${DEPLOYMENT:-$ROOT/deployments/base-sepolia.json}"
GRANT_AMOUNT_SKR="${GRANT_AMOUNT:-5000}"
OPERATORS_FILE="${OPERATORS_FILE:-$ROOT/operators.txt}"

if [ ! -f "$DEPLOYMENT" ]; then
  echo "[err] no deployment JSON at $DEPLOYMENT" >&2
  echo "      run scripts/deploy-sepolia.sh first" >&2
  exit 1
fi

parse() { python3 -c "import json; print(json.load(open('$DEPLOYMENT'))['contracts']['$1'])"; }
TOKEN=$(parse SKRToken)

# Build the recipient list
RECIPIENTS=()
if [ -n "${OPERATORS:-}" ]; then
  IFS=',' read -ra RECIPIENTS <<< "$OPERATORS"
elif [ -f "$OPERATORS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # strip comments and whitespace
    addr="${line%%#*}"
    addr="$(echo "$addr" | tr -d '[:space:]')"
    [ -z "$addr" ] && continue
    RECIPIENTS+=("$addr")
  done < "$OPERATORS_FILE"
else
  cat >&2 <<EOF
[err] no operators specified
  either:
    export OPERATORS=0xaaa...,0xbbb...,0xccc...
  or create $OPERATORS_FILE with one address per line (# comments ok)
EOF
  exit 1
fi

if [ "${#RECIPIENTS[@]}" -eq 0 ]; then
  echo "[err] operator list is empty" >&2
  exit 1
fi

# Convert SKR to wei (18 decimals)
GRANT_WEI=$(python3 -c "print(int(${GRANT_AMOUNT_SKR}) * 10**18)")

SENDER=$(cast wallet address --private-key "$PRIVATE_KEY")
SENDER_BAL=$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$SENDER" --rpc-url "$RPC_URL" | awk '{print $1}')
REQUIRED=$(python3 -c "print(${GRANT_WEI} * ${#RECIPIENTS[@]})")

echo "[..] grant plan"
echo "     sender        : $SENDER"
echo "     token         : $TOKEN"
echo "     grant / op    : $GRANT_AMOUNT_SKR SKR ($GRANT_WEI wei)"
echo "     recipients    : ${#RECIPIENTS[@]}"
echo "     total required: $REQUIRED wei"
echo "     sender balance: $SENDER_BAL wei"

# Compare as arbitrary-precision ints via python
if ! python3 -c "import sys; sys.exit(0 if int('$SENDER_BAL') >= int('$REQUIRED') else 1)"; then
  echo "[err] sender balance insufficient" >&2
  exit 1
fi

for addr in "${RECIPIENTS[@]}"; do
  # Basic address shape check
  if ! [[ "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "[err] not a valid hex address: $addr" >&2
    exit 1
  fi
done

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo
  echo "[dry-run] would send:"
  for addr in "${RECIPIENTS[@]}"; do
    printf "  %s  ← %s SKR\n" "$addr" "$GRANT_AMOUNT_SKR"
  done
  exit 0
fi

echo
for addr in "${RECIPIENTS[@]}"; do
  printf "[..] granting %s SKR → %s " "$GRANT_AMOUNT_SKR" "$addr"
  TX=$(cast send "$TOKEN" \
    "transfer(address,uint256)" \
    "$addr" "$GRANT_WEI" \
    --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" \
    --json | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])")
  printf "tx=%s\n" "$TX"
done

echo
echo "[ok] all ${#RECIPIENTS[@]} operator grants broadcast"
echo "     verify balances with:"
for addr in "${RECIPIENTS[@]}"; do
  echo "       cast call $TOKEN 'balanceOf(address)(uint256)' $addr --rpc-url \$RPC_URL"
done
