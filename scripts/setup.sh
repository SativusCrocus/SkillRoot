#!/usr/bin/env bash
#
# setup.sh — idempotent toolchain bootstrap for SkillRoot v0.
#
# Verifies (and installs, where practical) the full toolchain:
#   - Foundry (forge/cast/anvil)
#   - Node 20+ via nvm
#   - pnpm 9
#   - Rust (via rustup; needed for circom from source)
#   - Circom 2.1+
#   - snarkjs 0.7+
#
# Safe to re-run — all checks are gated by version detection.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# --- colour helpers (no external deps) ---------------------------------------
RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[0;33m"; BLU="\033[0;34m"; NC="\033[0m"
ok()   { printf "${GRN}[ok]${NC} %s\n"   "$*"; }
warn() { printf "${YEL}[warn]${NC} %s\n" "$*"; }
err()  { printf "${RED}[err]${NC} %s\n"  "$*" >&2; }
info() { printf "${BLU}[..]${NC} %s\n"   "$*"; }

# --- nvm shim ---------------------------------------------------------------
# nvm is not a real binary; it's a shell function. Source it if present.
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  # shellcheck disable=SC1090
  . "$HOME/.nvm/nvm.sh" || true
fi

# --- 1. Foundry --------------------------------------------------------------
if command -v forge >/dev/null 2>&1; then
  ok "forge $(forge --version | head -n1)"
else
  warn "forge not found — installing via foundryup"
  if ! command -v foundryup >/dev/null 2>&1; then
    info "installing foundryup"
    curl -L https://foundry.paradigm.xyz | bash
    export PATH="$HOME/.foundry/bin:$PATH"
  fi
  foundryup
  ok "forge $(forge --version | head -n1)"
fi

# --- 2. Node 20+ -------------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  if [ "$NODE_MAJOR" -ge 20 ]; then
    ok "node $(node -v)"
  else
    warn "node $(node -v) is too old; need ≥20"
    if command -v nvm >/dev/null 2>&1; then
      nvm install 20 && nvm use 20
      ok "node $(node -v)"
    else
      err "install nvm or upgrade node manually, then re-run"
      exit 1
    fi
  fi
else
  warn "node not found"
  if command -v nvm >/dev/null 2>&1; then
    nvm install 20 && nvm use 20
    ok "node $(node -v)"
  else
    err "install nvm (https://github.com/nvm-sh/nvm) then re-run"
    exit 1
  fi
fi

# --- 3. pnpm 9 ---------------------------------------------------------------
if command -v pnpm >/dev/null 2>&1; then
  PNPM_MAJOR="$(pnpm -v | awk -F. '{print $1}')"
  if [ "$PNPM_MAJOR" -ge 9 ]; then
    ok "pnpm $(pnpm -v)"
  else
    warn "pnpm $(pnpm -v) is too old; need ≥9"
    npm i -g pnpm@9
    ok "pnpm $(pnpm -v)"
  fi
else
  warn "pnpm not found — installing globally"
  npm i -g pnpm@9
  ok "pnpm $(pnpm -v)"
fi

# --- 4. Rust (for circom) ----------------------------------------------------
if command -v cargo >/dev/null 2>&1; then
  ok "rustc $(rustc --version | awk '{print $2}')"
else
  warn "cargo not found — installing via rustup"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shellcheck disable=SC1090
  . "$HOME/.cargo/env"
  ok "rustc $(rustc --version | awk '{print $2}')"
fi

# --- 5. Circom 2 -------------------------------------------------------------
if command -v circom >/dev/null 2>&1; then
  ok "circom $(circom --version | awk '{print $NF}')"
else
  warn "circom not found — building from source (this takes a minute)"
  TMPDIR_CIRCOM="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR_CIRCOM"' EXIT
  git clone --depth 1 https://github.com/iden3/circom.git "$TMPDIR_CIRCOM/circom"
  (cd "$TMPDIR_CIRCOM/circom" && cargo install --path circom)
  ok "circom $(circom --version | awk '{print $NF}')"
fi

# --- 6. snarkjs 0.7+ ---------------------------------------------------------
if command -v snarkjs >/dev/null 2>&1; then
  ok "snarkjs $(snarkjs --version 2>/dev/null | head -n1 || echo 'present')"
else
  warn "snarkjs not found — installing globally"
  npm i -g snarkjs@0.7.4
  ok "snarkjs installed"
fi

# --- 7. workspace deps -------------------------------------------------------
info "installing workspace dependencies via pnpm"
cd "$ROOT"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
ok "workspace ready"

# --- 8. contracts submodules -------------------------------------------------
info "syncing forge deps"
cd "$ROOT/contracts"
forge install --no-git --no-commit 2>/dev/null || true
forge build
ok "contracts build"

echo
ok "setup.sh complete — run ./scripts/build-circuits.sh next"
