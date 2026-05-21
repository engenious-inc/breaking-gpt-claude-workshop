#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1"; exit 1; }

echo "── Promptfoo Red-Team Workshop · setup ──"

# 1. Node.js >= 20
need_node_install=0
if command -v node >/dev/null 2>&1; then
  major="$(node -v | sed 's/v//' | cut -d. -f1)"
  if [ "$major" -lt 20 ]; then
    warn "Node $(node -v) found, need >= 20"
    need_node_install=1
  else
    ok "Node $(node -v)"
  fi
else
  warn "Node not found"
  need_node_install=1
fi

if [ "$need_node_install" -eq 1 ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      warn "Installing Homebrew…"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install node
  else
    err "Install Node 20+ from https://nodejs.org and re-run ./setup.sh"
  fi
  ok "Node $(node -v) installed"
fi

# 2. Warm npx cache for promptfoo
echo "Installing Promptfoo (via npx cache)…"
npx --yes promptfoo@latest --version >/dev/null
ok "Promptfoo ready"

# 3. .env
if [ ! -f .env ]; then
  cp .env.example .env
  echo
  echo "Get a free Groq API key at https://console.groq.com/keys"
  read -r -p "Paste your Groq API key (gsk-…): " groq_key
  if [ -n "$groq_key" ]; then
    # macOS sed needs '' after -i
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|GROQ_API_KEY=.*|GROQ_API_KEY=${groq_key}|" .env
    else
      sed -i "s|GROQ_API_KEY=.*|GROQ_API_KEY=${groq_key}|" .env
    fi
    ok "Wrote GROQ_API_KEY to .env"
  else
    warn "No key entered — edit .env manually before running eval"
  fi
else
  ok ".env already exists"
fi

# 4. Smoke test
echo "Running a 1-test smoke check…"
set -a; . ./.env; set +a
if npx --yes promptfoo@latest eval -c promptfooconfig.yaml --filter-first-n 1 --no-cache --no-write --no-table --no-progress-bar >/dev/null 2>&1; then
  ok "Smoke test passed"
else
  warn "Smoke test did not pass cleanly — see docs/03-troubleshooting.md"
fi

# 5. Next steps
echo
ok "Setup complete."
echo "Next:"
echo "  npx promptfoo@latest eval     # run the full workshop eval"
echo "  npx promptfoo@latest view     # open the web UI"
