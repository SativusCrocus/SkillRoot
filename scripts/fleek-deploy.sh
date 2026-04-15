#!/usr/bin/env bash
#
# fleek-deploy.sh — Week 7 dApp hosting: build the Next.js static export
# and push it to Fleek (IPFS).
#
# This script automates the local side of Fleek deployment:
#   1. ensures the frontend's .env.local is up-to-date with the current
#      deployment's contract addresses
#   2. runs `pnpm --filter @skillroot/app build` to produce app/out/
#   3. invokes the Fleek CLI to publish the static site
#
# The Fleek side of this (account, site slug, custom domain) is manual —
# see the "Manual prerequisites" block below. Once those are set up, this
# script can be run on every redeploy to ship a fresh dApp.
#
# Environment (optional):
#   DEPLOYMENT       - path to deployment JSON (default base-sepolia.json)
#   FLEEK_SITE_SLUG  - override the slug in fleek.json
#   SKIP_ENV_SYNC    - set to 1 to skip rewriting app/.env.local
#   SKIP_BUILD       - set to 1 to reuse app/out/
#
# ───────────────────────────────────────────────────────────────────────
# Manual prerequisites (do once):
#   1. sign up at https://fleek.xyz with a wallet or email
#   2. install the Fleek CLI: `npm i -g @fleek-platform/cli`
#   3. `fleek login`
#   4. `cd app && fleek sites init` — create/link the site to this repo
#      (this writes or updates app/fleek.json; commit it)
#   5. optionally set a custom domain via `fleek sites add-domain`
# ───────────────────────────────────────────────────────────────────────

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$ROOT/app"
DEPLOYMENT="${DEPLOYMENT:-$ROOT/deployments/base-sepolia.json}"

# Ensure node in PATH
if [ -d "$HOME/.nvm/versions/node" ]; then
  LATEST_NODE="$(ls -1 "$HOME/.nvm/versions/node" | sort -V | tail -n1)"
  export PATH="$HOME/.nvm/versions/node/$LATEST_NODE/bin:$PATH"
fi

RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[0;33m"; BLU="\033[0;34m"; NC="\033[0m"
ok()   { printf "${GRN}[ok]${NC} %s\n"   "$*"; }
info() { printf "${BLU}[..]${NC} %s\n"   "$*"; }
warn() { printf "${YEL}[warn]${NC} %s\n" "$*"; }
err()  { printf "${RED}[err]${NC} %s\n"  "$*" >&2; }

# --- 1. sync env vars from deployment JSON ----------------------------------
if [ "${SKIP_ENV_SYNC:-0}" = "1" ]; then
  info "SKIP_ENV_SYNC=1, using existing app/.env.local"
else
  if [ ! -f "$DEPLOYMENT" ]; then
    err "deployment JSON not found at $DEPLOYMENT"
    err "run scripts/deploy-sepolia.sh first, or set DEPLOYMENT to the right path"
    exit 1
  fi

  info "syncing app/.env.local from $DEPLOYMENT"
  APP_ENV="$APP/.env.local"
  # Preserve the ACTIVE_CHALLENGE_ID line if it already exists
  ACTIVE_ID=""
  if [ -f "$APP_ENV" ]; then
    ACTIVE_ID=$(grep -E '^NEXT_PUBLIC_ACTIVE_CHALLENGE_ID=' "$APP_ENV" | tail -n1 || true)
  fi

  python3 <<PY > "$APP_ENV"
import json, datetime
ZERO = "0x0000000000000000000000000000000000000000"
d = json.load(open("$DEPLOYMENT"))
c = d["contracts"]
print(f"# Synced by fleek-deploy.sh at {datetime.datetime.utcnow().isoformat()}Z")
print(f"# v0.2.0-no-vote: 8 canonical contracts")
print(f"NEXT_PUBLIC_CHAIN_ID={d.get('chainId', 84532)}")
print(f"NEXT_PUBLIC_SKR_TOKEN={c.get('SKRToken', ZERO)}")
print(f"NEXT_PUBLIC_STAKING_VAULT={c.get('StakingVault', ZERO)}")
print(f"NEXT_PUBLIC_CHALLENGE_REGISTRY={c.get('ChallengeRegistry', ZERO)}")
print(f"NEXT_PUBLIC_ATTESTATION_STORE={c.get('AttestationStore', ZERO)}")
print(f"NEXT_PUBLIC_ATTESTATION_ENGINE={c.get('AttestationEngine', ZERO)}")
print(f"NEXT_PUBLIC_QUERY_GATEWAY={c.get('QueryGateway', ZERO)}")
print(f"NEXT_PUBLIC_FRAUD_VERIFIER={c.get('FraudVerifier', c.get('FraudGroth16Verifier', ZERO))}")
print(f"NEXT_PUBLIC_FRAUD_VERIFIER_ADAPTER={c.get('FraudVerifierAdapter', ZERO)}")
PY

  if [ -n "$ACTIVE_ID" ]; then
    echo "$ACTIVE_ID" >> "$APP_ENV"
  fi
  ok "wrote $APP_ENV"
fi

# --- 2. build the static export ---------------------------------------------
if [ "${SKIP_BUILD:-0}" = "1" ]; then
  info "SKIP_BUILD=1, reusing existing app/out/"
  if [ ! -d "$APP/out" ]; then
    err "app/out/ does not exist — remove SKIP_BUILD and re-run"
    exit 1
  fi
else
  info "building Next.js static export"
  cd "$ROOT"
  if command -v pnpm >/dev/null 2>&1; then
    pnpm --filter @skillroot/app build
  else
    cd "$APP" && npm run build
  fi
  [ -d "$APP/out" ] || { err "build did not produce app/out/"; exit 1; }
  ok "static export at $APP/out/"
fi

# --- 3. fleek deploy ---------------------------------------------------------
if ! command -v fleek >/dev/null 2>&1; then
  warn "fleek CLI not found on PATH"
  warn "install with:  npm i -g @fleek-platform/cli"
  warn "then: fleek login && cd app && fleek sites init"
  warn ""
  warn "build artifacts are ready at $APP/out — you can ship them manually"
  warn "by dragging that folder into the Fleek dashboard."
  exit 2
fi

cd "$APP"

# Check we're logged in
if ! fleek whoami >/dev/null 2>&1; then
  err "not logged in to Fleek — run: fleek login"
  exit 1
fi

SITE_SLUG="${FLEEK_SITE_SLUG:-}"
if [ -z "$SITE_SLUG" ] && [ -f "$APP/fleek.json" ]; then
  SITE_SLUG=$(python3 -c "import json; print(json.load(open('$APP/fleek.json'))['sites'][0]['slug'])" 2>/dev/null || echo "")
fi
if [ -z "$SITE_SLUG" ]; then
  warn "no site slug found; fleek sites deploy will prompt interactively"
fi

info "deploying to Fleek (slug=${SITE_SLUG:-<prompt>})"
fleek sites deploy

ok "Fleek deployment dispatched"
echo
echo "Check the deployment status at:"
echo "  https://app.fleek.xyz/sites"
echo
echo "Once it's live, verify the IPFS gateway URL and (optionally) the"
echo "custom domain via 'fleek sites add-domain'."
