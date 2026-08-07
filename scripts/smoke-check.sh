#!/usr/bin/env bash
# Maintainer/instructor pre-cohort check: a live smoke-check across the whole
# workshop curriculum. Run from the repo root with a working GROQ_API_KEY in
# .env (./setup.sh sets this up). Intended for whoever preps a cohort run,
# not for students — bash-only by design (git-bash/WSL on Windows is fine
# for this one; students' own readiness check is preflight.sh/.ps1, which
# has full native Windows parity).
#
# Reports PASS/FAIL/SKIP per config and exits non-zero if anything is
# genuinely broken. "Broken" means promptfoo reported an error, crashed, or
# never produced a normal summary — NOT that some assertions failed. A
# red-team config where an attack lands (or a content probe that legitimately
# comes out differently this run) is expected behavior, not a smoke-check
# failure; those configs use inverted semantics on purpose (see CLAUDE.md).
#
# Paced three ways to stay under Groq's free-tier limits: --delay between calls
# (SMOKE_DELAY_MS, default 1500ms), -j 1 serialization, and a pause between
# configs (SMOKE_GAP_SECS, default 20s). Each config is also bounded by a
# per-config timeout, and a timed-out eval — together with its node child — is
# killed as a whole process tree so it can't keep throttling the rest of the run.
#
# Two modes:
#   ./scripts/smoke-check.sh                default: reads/writes promptfoo's disk
#                                           cache, so a throttled re-run resumes
#                                           from cache instead of re-hammering
#                                           Groq; same-day re-runs are near-free.
#   SMOKE_FRESH=1 ./scripts/smoke-check.sh  authoritative: --no-cache forces every
#                                           call live end-to-end. Run once, when
#                                           Groq is calm (e.g. the cohort morning).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if [ ! -f .env ]; then
  echo "No .env found — run ./setup.sh first." >&2
  exit 1
fi

pass=0
fail=0
skip=0
debugger_ok=0
timeout_count=0

# Seconds to pause between configs so Groq's per-minute budget recovers. Raise
# it (e.g. SMOKE_GAP_SECS=45) if you still see timeouts under heavier load.
GAP_SECS="${SMOKE_GAP_SECS:-20}"

# Milliseconds to wait between each promptfoo call (passed as --delay). With
# -j 1 this sets a spacing floor so even a fast model stays under Groq's
# ~30 req/min. Raise it (e.g. SMOKE_DELAY_MS=2500) under heavier load.
DELAY_MS="${SMOKE_DELAY_MS:-1500}"

# Default: read/write promptfoo's disk cache so a throttled re-run resumes
# instead of re-hammering Groq. SMOKE_FRESH=1 adds --no-cache for the
# authoritative pre-cohort run that validates the live Groq path end-to-end.
CACHE_FLAG=""
[ "${SMOKE_FRESH:-0}" = "1" ] && CACHE_FLAG="--no-cache"

# Track the in-flight eval so an interrupt kills it and cleans up (no orphaned
# npx/node child, no leftover tmpdir).
CURRENT_PID=""
CURRENT_TMPDIR=""

# Kill a process AND all its descendants. `npx promptfoo` runs the real eval in
# a node CHILD of the npx wrapper, so a plain `kill` on the wrapper pid orphans
# that child — which keeps calling Groq and throttles every later config into a
# cascade of timeouts. Recurse so nothing survives. Portable: pgrep -P works on
# macOS (BSD) and Linux; no `setsid`/GNU-only flags.
kill_tree() {
  local p="$1" child
  while IFS= read -r child; do
    [ -n "$child" ] && kill_tree "$child"
  done < <(pgrep -P "$p" 2>/dev/null)
  kill -9 "$p" 2>/dev/null
}

# shellcheck disable=SC2329 # invoked indirectly via `trap`, not called directly
cleanup_on_interrupt() {
  [ -n "$CURRENT_PID" ] && kill_tree "$CURRENT_PID"
  [ -n "$CURRENT_TMPDIR" ] && rm -rf "$CURRENT_TMPDIR"
  echo "" >&2
  echo "Interrupted — killed the in-flight eval (and its node child) and cleaned up." >&2
  exit 130
}
trap cleanup_on_interrupt INT TERM

# Configs expected to run with 0 promptfoo-reported errors on the default,
# keyless-beyond-Groq path.
CONFIGS=(
  "promptfooconfig.medibot.yaml"
  "promptfooconfig.finance.yaml"
  "promptfooconfig.quality.medibot.yaml"
  "promptfooconfig.quality.finance.yaml"
  "modules/00-promptfoo-basics/01-prompts/text/promptfooconfig.yaml"
  "modules/00-promptfoo-basics/01-prompts/multiline/promptfooconfig.yaml"
  "modules/00-promptfoo-basics/01-prompts/variables/promptfooconfig.yaml"
  "modules/00-promptfoo-basics/01-prompts/file-based/promptfooconfig.yaml"
  "modules/00-promptfoo-basics/02-providers/configuration/promptfooconfig.yaml"
  # Fails 2 of 6 by design (gpt-oss-20b leaks "Thinking:"). This check counts
  # promptfoo ERRORS, not failures, so a red-but-working lesson still belongs here.
  "modules/00-promptfoo-basics/02-providers/comparing-models/promptfooconfig.yaml"
  "modules/00-promptfoo-basics/03-assertions/contains/promptfooconfig.yaml"
  "modules/00-promptfoo-basics/03-assertions/regex/promptfooconfig.yaml"
  "modules/00-promptfoo-basics/03-assertions/factuality/promptfooconfig.yaml"
  "modules/00-promptfoo-basics/03-assertions/llm-rubric/promptfooconfig.yaml"
  "modules/02-advanced-eval/weights-and-metrics/promptfooconfig.yaml"
  "modules/02-advanced-eval/assert-sets-and-budgets/promptfooconfig.yaml"
  "modules/02-advanced-eval/exact-vs-fuzzy/promptfooconfig.yaml"
  "modules/02-advanced-eval/csv-driven-data/promptfooconfig.yaml"
  "modules/02-advanced-eval/fscore-classification/promptfooconfig.yaml"
  "modules/02-advanced-eval/temperature-and-personas/promptfooconfig.yaml"
  # Day 8 lesson. Its Arato POST is optional and skips cleanly when the env vars are
  # unset, so the custom provider still gets exercised here on every run.
  "modules/02-advanced-eval/observability/promptfooconfig.yaml"
)

# Opt-in configs needing a key/service not present by default — skipped, not failed.
SKIPPED=(
  "modules/00-promptfoo-basics/02-providers/local-model/promptfooconfig.yaml:needs LM Studio running on :1234"
  "modules/00-promptfoo-basics/03-assertions/answer-relevance/promptfooconfig.yaml:needs OPENAI_API_KEY (embeddings)"
  "promptfooconfig.openrouter.medibot.yaml:needs a valid OPENROUTER_API_KEY"
  "promptfooconfig.openrouter.finance.yaml:needs a valid OPENROUTER_API_KEY"
  "promptfooconfig.mybot.yaml:Challenge-3 slot — students overwrite it with their own bot, so its result is not a repo-health signal"
  "promptfooconfig.payflow.yaml:needs the PayFlow app running on :8000 — start it with ./run.sh payflow-serve"
  "promptfooconfig.payflow-multiturn.yaml:needs the PayFlow app running on :8000 — start it with ./run.sh payflow-serve"
  "promptfooconfig.payflow-redteam.yaml:needs the PayFlow app running, and is a 'redteam run' config rather than an 'eval -c' one"
)

# Intentionally-broken debugger fix-me stages — expected to NOT run clean.
DEBUGGER_CONFIGS=(
  "modules/02-advanced-eval/debugger/1_basic/promptfooconfig.yaml"
  "modules/02-advanced-eval/debugger/2_moderate/promptfooconfig.yaml"
  "modules/02-advanced-eval/debugger/3_advance/promptfooconfig.yaml"
)

# Runs one config, returns 0/1/2 via globals: ${STATUS} = OK | ERRORS:<n> | CRASHED
run_config() {
  local cfg="$1"
  # mktemp's X-substitution doesn't reliably honor a literal suffix after the
  # X run on macOS's bundled (BSD) mktemp, so get a unique directory instead
  # and use a fixed filename inside it — portable and gives promptfoo's -o
  # flag the .json extension it validates.
  local tmpdir
  tmpdir=$(mktemp -d)
  CURRENT_TMPDIR="$tmpdir"
  local tmpfile="$tmpdir/result.json"
  local outfile="$tmpdir/stdout.log"
  local timeout_secs=90

  # Portable per-config timeout (no dependency on GNU `timeout`, which macOS
  # lacks by default): run in the background, poll, kill if it overruns. This
  # is exactly the guard that would have made today's Groq queue-throttling
  # visible as "TIMEOUT" instead of silently stalling the whole sweep.
  # $CACHE_FLAG is intentionally word-split: "" -> nothing, "--no-cache" -> one
  # flag. A string var, not a bash array — an empty array under `set -u` errors
  # on macOS's stock bash 3.2, which this script must run on. The value has no
  # spaces/globs, so the split is safe and deliberate.
  # shellcheck disable=SC2086
  npx promptfoo@latest eval -c "$cfg" -j 1 --delay "$DELAY_MS" --no-progress-bar --no-table --no-share $CACHE_FLAG -o "$tmpfile" >"$outfile" 2>&1 &
  local pid=$!
  CURRENT_PID="$pid"
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$timeout_secs" ]; then
      kill_tree "$pid"
      wait "$pid" 2>/dev/null
      rm -rf "$tmpdir"
      CURRENT_PID=""; CURRENT_TMPDIR=""
      STATUS="TIMEOUT"
      STATUS_DETAIL="killed after ${timeout_secs}s — likely Groq queue throttling from heavy same-day usage, not necessarily a config bug. Re-run this config alone later to confirm."
      return
    fi
  done
  wait "$pid"
  local exit_code=$?
  local out
  out=$(cat "$outfile")
  rm -rf "$tmpdir"
  CURRENT_PID=""; CURRENT_TMPDIR=""

  local errors
  # Output-phrasing parse ("N errors") verified against promptfoo v0.121.18.
  errors=$(echo "$out" | grep -oE '[0-9]+ errors?' | grep -oE '^[0-9]+' | head -1)

  if [ -z "$errors" ]; then
    STATUS="CRASHED"
    STATUS_DETAIL="$out"
    return
  fi
  if [ "$errors" = "0" ] && { [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 100 ]; }; then
    STATUS="OK"
    return
  fi
  STATUS="ERRORS:$errors"
  STATUS_DETAIL="$out"
}

echo "== Smoke-check: curriculum live sanity pass =="
echo ""

for cfg in "${CONFIGS[@]}"; do
  printf "  %-72s " "$cfg"
  run_config "$cfg"
  if [ "$STATUS" = "OK" ]; then
    echo "OK"
    pass=$((pass + 1))
  elif [ "$STATUS" = "TIMEOUT" ]; then
    echo "TIMEOUT (inconclusive — see note below, not counted as broken)"
    echo "  $STATUS_DETAIL"
    timeout_count=$((timeout_count + 1))
  else
    echo "BROKEN ($STATUS)"
    echo "$STATUS_DETAIL" | tail -20
    fail=$((fail + 1))
  fi
  sleep "$GAP_SECS"
done

echo ""
echo "-- Skipped (opt-in, need an external key/service) --"
for entry in "${SKIPPED[@]}"; do
  cfg="${entry%%:*}"
  reason="${entry#*:}"
  echo "  SKIP  $cfg — $reason"
  skip=$((skip + 1))
done

echo ""
echo "-- Debugger fix-me stages (expected to stay broken — confirms the exercise still works) --"
for cfg in "${DEBUGGER_CONFIGS[@]}"; do
  printf "  %-72s " "$cfg"
  run_config "$cfg"
  if [ "$STATUS" = "OK" ]; then
    echo "UNEXPECTEDLY RAN CLEAN — this stage may have been accidentally fixed, check it"
    fail=$((fail + 1))
  elif [ "$STATUS" = "TIMEOUT" ]; then
    echo "TIMEOUT — inconclusive, can't confirm the planted bug this run; re-run alone later"
    timeout_count=$((timeout_count + 1))
  else
    echo "correctly still broken ($STATUS)"
    debugger_ok=$((debugger_ok + 1))
  fi
  sleep "$GAP_SECS"
done

echo ""
echo "== Summary =="
echo "  $pass configs ran clean (0 errors)"
echo "  $fail configs BROKEN"
echo "  $skip configs skipped (opt-in, documented reason)"
echo "  $timeout_count configs TIMED OUT (inconclusive — likely Groq throttling, re-run alone later)"
echo "  $debugger_ok/3 debugger fix-me stages correctly still broken"

if [ "$fail" -gt 0 ]; then
  echo ""
  echo "SMOKE CHECK FAILED — see BROKEN entries above."
  exit 1
fi
if [ "$timeout_count" -gt 0 ]; then
  echo ""
  echo "SMOKE CHECK INCONCLUSIVE — $timeout_count config(s) timed out (see above). No confirmed breaks, but re-run the timed-out configs alone once Groq load clears before trusting this a full PASS."
  exit 2
fi
echo ""
echo "SMOKE CHECK PASSED."
exit 0
