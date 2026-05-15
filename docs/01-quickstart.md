# Quickstart

1. Clone this repo and `cd` into it.
2. Run `./setup.sh` (macOS/Linux) or `.\setup.ps1` (Windows).
3. Paste your OpenAI API key when prompted.
4. `npx promptfoo@latest eval` — runs all workshop tests.
5. `npx promptfoo@latest view` — opens the result UI in your browser.

## File map

| File | What it does |
|---|---|
| `promptfooconfig.yaml` | Defines providers, prompts, and which tests to run |
| `scripts/create-assistant.js` | Creates the MediBot Assistant in your OpenAI account |
| `prompts/system-helpful.txt` | (Reference only) baseline loose assistant prompt |
| `prompts/system-strict.txt` | (Reference only) guardrailed prompt; MediBot uses similar rules |
| `tests/jailbreaks.yaml` | Prompt-injection / guardrail-bypass cases |
| `tests/hallucinations.yaml` | Made-up-fact traps |
| `tests/cost-context.yaml` | Token / cost / latency assertions |

## Enabling GPT vs Claude

1. Add `ANTHROPIC_API_KEY=sk-ant-...` to `.env`.
2. Uncomment the `anthropic:messages:claude-haiku-4-5` block in `promptfooconfig.yaml`.
3. Re-run `npx promptfoo@latest eval`. The UI will show side-by-side outputs and per-test pass/fail per provider.
