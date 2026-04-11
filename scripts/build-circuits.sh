#!/usr/bin/env bash
#
# build-circuits.sh — compile circom circuits, run groth16 setup, and
# copy the emitted Solidity verifier into contracts/src/verifiers/.
#
# Assumes scripts/ceremony.sh (or an equivalent download) has placed
# pot14_final.ptau at circuits/ptau/pot14_final.ptau.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CIRCUITS="$ROOT/circuits"
CONTRACTS="$ROOT/contracts"

PTAU="$CIRCUITS/ptau/pot14_final.ptau"

if [ ! -f "$PTAU" ]; then
  echo "[err] missing $PTAU — run ./scripts/ceremony.sh first" >&2
  exit 1
fi

# --- math circuit ------------------------------------------------------------
echo "[..] building math circuit"
bash "$CIRCUITS/math/build.sh"

# --- verifier copy -----------------------------------------------------------
SRC="$CIRCUITS/math/build/MathVerifier.sol"
DEST="$CONTRACTS/src/verifiers/MathVerifier.sol"

if [ ! -f "$SRC" ]; then
  echo "[err] MathVerifier.sol not found at $SRC — circuit build failed" >&2
  exit 1
fi

# Rename the snarkjs-emitted Groth16Verifier to MathGroth16Verifier so it
# doesn't collide with any other verifier in the codebase. Idempotent.
echo "[..] installing MathVerifier.sol → contracts/src/verifiers/"
mkdir -p "$(dirname "$DEST")"
sed 's/contract Groth16Verifier/contract MathGroth16Verifier/' "$SRC" > "$DEST"

# --- rebuild contracts to pick up the new verifier --------------------------
echo "[..] forge build (post-verifier)"
cd "$CONTRACTS"
forge build

echo "[ok] circuits built and verifier installed"
echo "     artifacts: $CIRCUITS/math/build/"
echo "     verifier:  $DEST"
