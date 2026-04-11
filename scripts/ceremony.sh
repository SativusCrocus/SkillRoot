#!/usr/bin/env bash
#
# ceremony.sh — fetch the Hermez pot14 Powers of Tau file and (optionally) run
# a single-party phase 2 contribution for v0.
#
# v0 NOTE: phase 2 is deliberately single-party in testnet. Pre-mainnet, a real
# ceremony with ≥3 external contributors must be run — see docs/threat-model.md
# and docs/ROADMAP.md (P0 item).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PTAU_DIR="$ROOT/circuits/ptau"
PTAU_FILE="$PTAU_DIR/pot14_final.ptau"
URL="https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_14.ptau"
EXPECTED_SIZE_BYTES=19816508  # approx sanity check (~18.9 MB)

mkdir -p "$PTAU_DIR"

if [ -f "$PTAU_FILE" ]; then
  SIZE=$(stat -f%z "$PTAU_FILE" 2>/dev/null || stat -c%s "$PTAU_FILE")
  if [ "$SIZE" -ge 1000000 ]; then
    echo "[ok] pot14_final.ptau already present ($SIZE bytes)"
  else
    echo "[warn] pot14_final.ptau looks truncated, re-downloading"
    rm -f "$PTAU_FILE"
  fi
fi

if [ ! -f "$PTAU_FILE" ]; then
  echo "[..] downloading pot14 from Hermez mirror"
  echo "     $URL"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar -o "$PTAU_FILE" "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$PTAU_FILE" "$URL"
  else
    echo "[err] need curl or wget to download the ptau file" >&2
    exit 1
  fi
  SIZE=$(stat -f%z "$PTAU_FILE" 2>/dev/null || stat -c%s "$PTAU_FILE")
  echo "[ok] downloaded $SIZE bytes to $PTAU_FILE"
fi

# --- phase-2 contribution -----------------------------------------------------
# build-circuits.sh runs phase 2 per-circuit inside circuits/math/build.sh —
# this script just makes sure the phase 1 file is available. If invoked with
# --contribute, we also tee out an entropy-commitment file for the record.

if [ "${1:-}" = "--contribute" ]; then
  ENTROPY_FILE="$PTAU_DIR/phase2-entropy-commitment.txt"
  if [ ! -f "$ENTROPY_FILE" ]; then
    ENTROPY="$(openssl rand -hex 32)"
    {
      echo "SkillRoot v0 phase-2 contribution commitment"
      echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "entropy-sha256: $(printf '%s' "$ENTROPY" | shasum -a 256 | awk '{print $1}')"
      echo "(raw entropy intentionally NOT recorded — it must be destroyed after use)"
    } > "$ENTROPY_FILE"
    echo "[ok] wrote entropy commitment → $ENTROPY_FILE"
  else
    echo "[ok] entropy commitment already exists at $ENTROPY_FILE"
  fi
fi

echo "[ok] ceremony.sh done — run ./scripts/build-circuits.sh next"
