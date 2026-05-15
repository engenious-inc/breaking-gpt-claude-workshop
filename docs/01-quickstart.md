# Quickstart

1. Clone this repo and `cd` into it.
2. Run `./setup.sh` (macOS/Linux) or `.\setup.ps1` (Windows).
3. Paste your OpenAI API key when prompted.
4. `npx promptfoo@latest eval` — runs all workshop tests.
5. `npx promptfoo@latest view` — opens the result UI in your browser.

## File map

| File | What it does |
|---|---|
| `promptfooconfig.yaml` | MediBot eval config (default) |
| `promptfooconfig.finance.yaml` | FinanceBot eval config (run with `-c`) |
| `prompts/medibot.txt` | MediBot's system prompt — healthcare triage |
| `prompts/financebot.txt` | FinanceBot's system prompt — retail brokerage |
| `tests/jailbreaks.yaml` | MediBot prompt-injection / guardrail-bypass cases |
| `tests/finance-jailbreaks.yaml` | FinanceBot prompt-injection / guardrail-bypass cases |
| `tests/hallucinations.yaml` | Made-up-fact traps (domain-neutral, shared) |
| `tests/cost-context.yaml` | Token / cost / latency assertions (shared) |

## Enabling GPT vs Claude

1. Add `ANTHROPIC_API_KEY=sk-ant-...` to `.env`.
2. Uncomment the `anthropic:messages:claude-haiku-4-5` block in `promptfooconfig.yaml`.
3. Re-run `npx promptfoo@latest eval`. The UI will show side-by-side outputs and per-test pass/fail per provider.
