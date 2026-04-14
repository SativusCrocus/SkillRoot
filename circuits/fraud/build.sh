#!/usr/bin/env bash
# build.sh — compile fraud.circom, run the Groth16 trusted setup, and export
# a Solidity verifier contract.
#
# Prerequisites:
#   - circom 2.1.x on PATH
#   - snarkjs 0.7.x on PATH (or callable via `npx snarkjs`)
#   - circomlib installed as a node_modules sibling (see scripts/package.json)
#   - pot14_final.ptau downloaded to ../ptau/ (see ../../scripts/ceremony.sh)
#
# Outputs (all in ./build/):
#   fraud.r1cs, fraud.wasm, fraud_final.zkey, FraudVerifier.sol
#
# After this runs successfully, copy FraudVerifier.sol to
# contracts/src/verifiers/ and the FraudVerifierAdapter wraps its fixed-size
# signature for the dynamic IZKVerifier interface.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/build"
PTAU="$HERE/../ptau/pot14_final.ptau"
CIRCOMLIB="$HERE/../node_modules/circomlib/circuits"

mkdir -p "$BUILD"

if [ ! -d "$CIRCOMLIB" ]; then
    echo "error: circomlib not found at $CIRCOMLIB"
    echo "run: cd $HERE/.. && npm init -y && npm install circomlib@2.0.5"
    exit 1
fi
if [ ! -f "$PTAU" ]; then
    echo "error: $PTAU not found. run scripts/ceremony.sh first"
    exit 1
fi

echo "[1/5] compile fraud.circom"
circom "$HERE/fraud.circom" \
    --r1cs --wasm --sym \
    -o "$BUILD" \
    -l "$CIRCOMLIB"

echo "[2/5] groth16 setup"
snarkjs groth16 setup \
    "$BUILD/fraud.r1cs" \
    "$PTAU" \
    "$BUILD/fraud_0000.zkey"

echo "[3/5] phase 2 contribution"
snarkjs zkey contribute \
    "$BUILD/fraud_0000.zkey" \
    "$BUILD/fraud_final.zkey" \
    -n="skillroot v0.2.0-no-vote single contributor" \
    -e="$(openssl rand -hex 32)"

echo "[4/5] export verification key"
snarkjs zkey export verificationkey \
    "$BUILD/fraud_final.zkey" \
    "$BUILD/verification_key.json"

echo "[5/5] export Solidity verifier"
snarkjs zkey export solidityverifier \
    "$BUILD/fraud_final.zkey" \
    "$BUILD/FraudVerifier.sol"

# Normalize the contract name + pragma to match our repo
sed -i.bak 's/contract Groth16Verifier/contract FraudGroth16Verifier/' "$BUILD/FraudVerifier.sol"
sed -i.bak 's|pragma solidity.*|pragma solidity 0.8.24;|' "$BUILD/FraudVerifier.sol"
rm -f "$BUILD/FraudVerifier.sol.bak"

echo ""
echo "done. artifacts in $BUILD/:"
ls -la "$BUILD/"
echo ""
echo "next: copy FraudVerifier.sol to contracts/src/verifiers/ and rebuild"
