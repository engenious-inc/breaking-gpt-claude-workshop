# Breaking GPT & Claude — Promptfoo Red-Team Workshop

Hands-on AI bug-bounty workshop. You'll red-team two chatbots — **MediBot** (healthcare triage) and **FinanceBot** (retail brokerage) — using [Promptfoo](https://www.promptfoo.dev). Both are built the way most production AI assistants are built: a Llama 3.3 70B model + a guardrail system prompt, served via Groq's free tier. Same attack surface, different domain rules. Optionally compare against GPT-4o-mini or Claude (both paid).

<p align="center">
  <img src="docs/qr.png" alt="Scan to clone" width="220" />
</p>

## Quickstart (≈ 3 minutes)

You need: a terminal, internet, and a free [Groq API key](https://console.groq.com/keys).

### macOS / Linux
```bash
git clone https://github.com/gregorygold/breaking-gpt-claude-workshop.git
cd breaking-gpt-claude-workshop
./setup.sh
```

### Windows (PowerShell)
```powershell
git clone https://github.com/gregorygold/breaking-gpt-claude-workshop.git
cd breaking-gpt-claude-workshop
.\setup.ps1
```

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
4. **Multi-model comparison** — uncomment additional Groq, OpenAI, or Anthropic providers in `promptfooconfig.yaml` for side-by-side runs

## Troubleshooting

See [docs/03-troubleshooting.md](docs/03-troubleshooting.md).
