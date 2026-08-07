#!/usr/bin/env bash
# One-command workshop eval runner.
#
# Maps a short target name to its Promptfoo config, bakes in free-tier-safe
# pacing (-j 1 --delay 1000 by default, so a whole room stays under Groq's
# ~30 req/min limit), and — because these are RED-TEAM suites where a *failing*
# assertion means the attack landed — translates Promptfoo's exit code into a
# plain-English verdict. Extra args after the target pass straight through.
#
#   ./run.sh medibot                     # MediBot red-team suite
#   ./run.sh finance --filter-first-n 1  # extra args pass through to promptfoo
#   ./run.sh view                        # open the results web UI
#   ./run.sh --list                      # show all targets
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Pacing defaults keep a full room under Groq's ~30 req/min free-tier limit.
JOBS="${RUN_JOBS:-1}"
DELAY_MS="${RUN_DELAY_MS:-1000}"

usage() {
  cat <<'EOF'
Usage: ./run.sh <target> [extra promptfoo args…]

Targets:
  medibot             MediBot red-team suite (free-tier-safe)
  finance             FinanceBot red-team suite
  quality.medibot     MediBot quality challenges (bias / consistency / compliance)
  quality.finance     FinanceBot quality challenges (context / values)
  openrouter.medibot  MediBot via the OpenRouter fallback (needs OPENROUTER_API_KEY)
  openrouter.finance  FinanceBot via the OpenRouter fallback
  mybot               Your Challenge-3 build-it bot
  payflow             PayFlow app suite — guard, routing, citations (server must be up)
  payflow-multiturn   PayFlow injection after 4 turns of legitimate context
  payflow-redteam     PayFlow generated red team (promptfoo redteam run — slow)
  payflow-serve       Start the PayFlow demo app on :8000 (foreground)
  payflow-health      Check the PayFlow app is answering before you eval
  view                Open the results web UI

Examples:
  ./run.sh medibot
  ./run.sh finance --filter-first-n 1
  ./run.sh payflow-serve      # in one terminal
  ./run.sh payflow            # in another
  ./run.sh payflow-multiturn
  ./run.sh payflow-redteam
  ./run.sh view

Pacing defaults to -j 1 --delay 1000 (override with RUN_JOBS / RUN_DELAY_MS).
EOF
}

target="${1:-}"
case "$target" in
  ""|-h|--help|--list) usage; exit 0 ;;
esac
shift

# `view` opens the report UI — no eval, no verdict.
if [ "$target" = "view" ]; then
  exec npx --yes promptfoo@latest view "$@"
fi

PAYFLOW_URL="http://localhost:${PAYFLOW_PORT:-8000}"

# The PayFlow app is a server, not a config. These two targets run it rather than eval it.
if [ "$target" = "payflow-serve" ]; then
  [ -f .env ] && { set -a; . ./.env; set +a; }
  exec node modules/03-app-testing/payflow/server.js "$@"
fi

if [ "$target" = "payflow-health" ]; then
  if node -e "fetch('${PAYFLOW_URL}/health').then(r=>r.json()).then(j=>{console.log(JSON.stringify(j));process.exit(j.status==='ok'?0:1)}).catch(()=>process.exit(1))" 2>/dev/null; then
    printf "${GREEN}✓${NC} PayFlow app is up at %s\n" "$PAYFLOW_URL"
    exit 0
  fi
  printf "${RED}✗${NC} PayFlow app is not answering at %s — start it with ${BLUE}./run.sh payflow-serve${NC}\n" "$PAYFLOW_URL" >&2
  exit 1
fi

# `redteam run` generates attacks before it evaluates them, so it is its own subcommand
# rather than an `eval -c`.
if [ "$target" = "payflow-redteam" ]; then
  [ -f .env ] && { set -a; . ./.env; set +a; }
  if ! node -e "fetch('${PAYFLOW_URL}/health').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>/dev/null; then
    printf "${RED}✗${NC} PayFlow app is not answering at %s.\n" "$PAYFLOW_URL" >&2
    printf "  Start it in another terminal first:  ${BLUE}./run.sh payflow-serve${NC}\n" >&2
    exit 2
  fi
  printf "${BLUE}▶${NC} Generating and running the PayFlow red team.\n"
  printf "  Every probe runs the full pipeline — three Groq calls each. Expect this to take a while.\n"
  printf "  Reminder: a ${YELLOW}failing${NC} check means the attack landed. That's the finding.\n\n"
  ec=0
  # OPENAI_API_KEY is unset for this run on purpose. Nothing here uses OpenAI — but
  # promptfoo treats the key's mere presence as "generate attacks locally" and switches
  # off its own remote generator, which several strategies require. The whole scan then
  # dies with "requires remote generation". The key is optional in this repo (only the
  # paid comparison block in promptfooconfig.medibot.yaml reads it), so dropping it here
  # costs nothing and keeps every strategy available.
  env -u OPENAI_API_KEY npx --yes promptfoo@latest redteam run -c promptfooconfig.payflow-redteam.yaml "$@" || ec=$?
  echo
  case "$ec" in
    0)   printf "${GREEN}🛡  Exit 0 — nothing landed on this run.${NC}\n" ;;
    100) printf "${YELLOW}⚠  Exit 100 — at least one attack landed. Triage it: ${BLUE}./run.sh view${NC}\n" ;;
    *)   printf "${RED}✗ Exit %s — an actual error.${NC}\n" "$ec" ;;
  esac
  exit "$ec"
fi

case "$target" in
  medibot|finance|quality.medibot|quality.finance|openrouter.medibot|openrouter.finance|mybot|payflow|payflow-multiturn)
    cfg="promptfooconfig.${target}.yaml" ;;
  *)
    printf "${RED}✗${NC} Unknown target: %s\n\n" "$target" >&2
    usage >&2
    exit 2 ;;
esac

if [ ! -f "$cfg" ]; then
  printf "${RED}✗${NC} Config not found: %s — are you in the repo root?\n" "$cfg" >&2
  exit 2
fi

# Load .env so GROQ_API_KEY / OPENROUTER_API_KEY reach Promptfoo.
if [ -f .env ]; then
  set -a; . ./.env; set +a
else
  printf "${YELLOW}!${NC} No .env found — run ./setup.sh first (or export GROQ_API_KEY).\n" >&2
fi

printf "${BLUE}▶${NC} Running ${BLUE}%s${NC}  ${YELLOW}(-j %s --delay %sms)${NC}\n" "$target" "$JOBS" "$DELAY_MS"

# PayFlow is an ordinary suite — pass means good. Every other target here is a red-team
# suite where a failing assertion IS the finding. Saying the wrong one teaches the
# opposite of the lesson, so the two verdicts are kept apart.
if [ "$target" = "payflow" ] || [ "$target" = "payflow-multiturn" ]; then
  if ! node -e "fetch('${PAYFLOW_URL}/health').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>/dev/null; then
    printf "${RED}✗${NC} PayFlow app is not answering at %s.\n" "$PAYFLOW_URL" >&2
    printf "  Start it in another terminal first:  ${BLUE}./run.sh payflow-serve${NC}\n" >&2
    printf "  Without it every case fails with a connection error that looks like a bug in your tests.\n" >&2
    exit 2
  fi
  printf "  Testing the ${BLUE}application${NC}, not a model — assertions read output.route and output.citations.\n\n"
else
  printf "  Reminder: these are red-team suites — a ${YELLOW}failing${NC} check means the model did the thing you were testing for. That's the finding, not an error.\n\n"
fi

ec=0
# shellcheck disable=SC2086
npx --yes promptfoo@latest eval -c "$cfg" -j "$JOBS" --delay "$DELAY_MS" "$@" || ec=$?

echo
if [ "$target" = "payflow" ] || [ "$target" = "payflow-multiturn" ]; then
  case "$ec" in
    0)   printf "${GREEN}✓ Exit 0 — the pipeline behaved on every case.${NC}\n"
         printf "  Guard fired where it should, routing picked the right specialist, citations lined up.\n" ;;
    100) printf "${YELLOW}✗ Exit 100 — one or more checks failed. Here that IS a defect.${NC}\n"
         printf "  Look at which assertion broke:  ${BLUE}./run.sh view${NC}\n" ;;
    *)   printf "${RED}✗ Exit %s — an actual error.${NC}\n" "$ec"
         printf "  Is the app still up?  ${BLUE}./run.sh payflow-health${NC}\n" ;;
  esac
  exit "$ec"
fi

case "$ec" in
  0)
    printf "${GREEN}🛡  Exit 0 — every guardrail held on this run.${NC}\n"
    printf "  Nothing landed. Try a tougher attack, a different model, or add your own case under tests/.\n" ;;
  100)
    printf "${GREEN}✓ Exit 100 — one or more checks failed. That's the finding.${NC}\n"
    printf "  See which model broke on which case:  ${BLUE}./run.sh view${NC}\n" ;;
  *)
    printf "${RED}✗ Exit %s — that's an actual error, not a finding.${NC}\n" "$ec"
    printf "  Usually a key / network / throttle issue — see docs/03-troubleshooting.md.\n" ;;
esac
exit "$ec"
