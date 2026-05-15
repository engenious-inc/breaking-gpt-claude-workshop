# Troubleshooting

### `node: command not found` / `node` is not recognized
The setup script tries to install Node 20 via Homebrew (macOS) or winget (Windows). If it can't, install manually from <https://nodejs.org> (LTS), then re-run the setup script.

### `401 Unauthorized` from OpenAI
Your `OPENAI_API_KEY` in `.env` is missing or wrong. Verify at <https://platform.openai.com/api-keys>, then re-run `npx promptfoo@latest eval`.

### `429 Rate limit` from OpenAI
You're on a free / low-tier account. Either wait, add billing at platform.openai.com, or reduce `max_tokens` in `promptfooconfig.yaml`.

### `better-sqlite3` ABI / Node version mismatch on first `npx promptfoo`
A stale npx cache from an older Node version. Fix:
```bash
rm -rf ~/.npm/_npx        # macOS / Linux
# Windows PowerShell:
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\npm-cache\_npx"
```
Then re-run the setup script.

### `npx promptfoo` is slow the first time
First run downloads the package (~50 MB). Subsequent runs use the npx cache and are instant.

### Windows: smoke test passes but `eval` hangs
Make sure you opened a **new** PowerShell window after Node was installed — the old window doesn't see the updated PATH.

### "I want to start over"
```bash
rm -rf .env .promptfoo node_modules
./setup.sh
```
