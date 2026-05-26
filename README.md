# Breaking GPT & Claude — Promptfoo Red-Team Workshop

Hands-on AI bug-bounty workshop. You'll red-team two chatbots — **MediBot** (healthcare triage) and **FinanceBot** (retail brokerage) — using [Promptfoo](https://www.promptfoo.dev). Both are built the way most production AI assistants are built: an open-weight LLM + a guardrail system prompt, served via Groq's free tier. Same attack surface, different domain rules.

The default config runs a six-way side-by-side comparison across Groq's free catalog — three Meta Llama variants (3.1-8B, 3.3-70B, Llama-4-Scout-17B) and three OpenAI open-weight gpt-oss models (20B, 120B, safeguard-20B). Optionally add the paid `openai:gpt-4o-mini` or `anthropic:claude-haiku-4-5` for cross-vendor comparison.

<p align="center">
  <img src="docs/qr.png" alt="Scan to clone" width="220" />
</p>

## Quickstart (≈ 3 minutes)

You need: a terminal, internet, and a free [Groq API key](https://console.groq.com/keys).

### macOS / Linux
```bash
git clone https://github.com/engenious-inc/breaking-gpt-claude-workshop.git
cd breaking-gpt-claude-workshop
./setup.sh
```

### Windows (PowerShell)
```powershell
git clone https://github.com/engenious-inc/breaking-gpt-claude-workshop.git
cd breaking-gpt-claude-workshop
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

> If `.\setup.ps1` fails with *"running scripts is disabled on this system"*, use the `-ExecutionPolicy Bypass` invocation shown above (or run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first).

The script will: check Node ≥ 20, install Promptfoo, prompt for your Groq key, write `.env`, and run a smoke test.

## Run the workshop eval

```bash
npx promptfoo@latest eval                                  # MediBot (default)
npx promptfoo@latest eval -c promptfooconfig.finance.yaml  # FinanceBot
npx promptfoo@latest view                                  # opens the web UI
```

## What you'll do

1. **Prompt-injection / jailbreaks** — try to bypass system-prompt guardrails (`tests/jailbreaks.yaml`)
2. **Hallucination traps** — confirm the model refuses to invent facts (`tests/hallucinations.yaml`)
3. **Cost & context** — assert token usage, cost, and latency thresholds (`tests/cost-context.yaml`)
4. **Multi-model comparison** — six Groq-hosted models run by default. Uncomment the paid `openai:gpt-4o-mini` or `anthropic:messages:claude-haiku-4-5` lines in `promptfooconfig.yaml` to add closed-weight vendors. Add their keys to `.env` first.

### Notes on the default lineup

- All six default providers run on Groq's free tier (~30 req/min per key). A full eval issues ≈ 6 × tests calls; expect ~30–60s for a single test file.
- gpt-oss models emit hidden reasoning tokens, so they spend ~2× the tokens of the Llama models per response. The `cost` assertions in `tests/cost-context.yaml` are dollar thresholds — Groq reports `$0` on free-tier calls, so they pass trivially regardless. The `javascript` length assertion (≤ 40 words) can fail for the more verbose gpt-oss models — that's intentional, it's a signal you're meant to spot.
- The default grader (judge LLM for `llm-rubric` assertions) is `groq:llama-3.3-70b-versatile`, set via `defaultTest.options.provider`. Workshop attendees don't need an OpenAI key for grading.

## Troubleshooting

See [docs/03-troubleshooting.md](docs/03-troubleshooting.md).
