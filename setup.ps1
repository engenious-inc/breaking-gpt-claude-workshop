#requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Ok($m)   { Write-Host "✓ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "! $m" -ForegroundColor Yellow }
function Err($m)  { Write-Host "✗ $m" -ForegroundColor Red; exit 1 }

Write-Host "── Promptfoo Red-Team Workshop · setup ──"

# 1. Node.js >= 20
$needNode = $false
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
  $ver = (node -v) -replace 'v',''
  $major = [int]($ver.Split('.')[0])
  if ($major -lt 20) { Warn "Node v$ver found, need >= 20"; $needNode = $true }
  else { Ok "Node v$ver" }
} else {
  Warn "Node not found"; $needNode = $true
}

if ($needNode) {
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) { Err "Install Node 20+ from https://nodejs.org and re-run .\setup.ps1" }
  Warn "Installing Node via winget…"
  winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
  Ok "Node installed — open a NEW PowerShell window and re-run .\setup.ps1"
  exit 0
}

# 2. Warm npx cache
Write-Host "Installing Promptfoo (via npx cache)…"
& npx --yes promptfoo@latest --version | Out-Null
Ok "Promptfoo ready"

# 3. .env
if (-not (Test-Path .env)) {
  Copy-Item .env.example .env
  Write-Host ""
  Write-Host "Get a free Groq API key at https://console.groq.com/keys"
  $key = Read-Host "Paste your Groq API key (gsk-…)"
  if ($key) {
    (Get-Content .env) -replace '^GROQ_API_KEY=.*', "GROQ_API_KEY=$key" | Set-Content .env
    Ok "Wrote GROQ_API_KEY to .env"
  } else {
    Warn "No key entered — edit .env manually before running eval"
  }
} else {
  Ok ".env already exists"
}

# Load .env into current process for smoke test
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([^#=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), 'Process')
  }
}

# 4. Smoke test
Write-Host "Running a 1-test smoke check…"
& npx --yes promptfoo@latest eval -c promptfooconfig.yaml --filter-first-n 1 --no-cache --no-write --no-table --no-progress-bar *> $null
# promptfoo exits 100 when assertions fail; the workshop is designed so some attacks succeed and others fail per model, so 100 is expected on a healthy setup.
if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 100) {
  Ok "Smoke test passed (Groq reachable)"
} else {
  Warn "Smoke test failed (exit $LASTEXITCODE) — see docs/03-troubleshooting.md"
}

# 5. Next steps
Write-Host ""
Ok "Setup complete."
Write-Host "Next:"
Write-Host "  npx promptfoo@latest eval     # run the full workshop eval"
Write-Host "  npx promptfoo@latest view     # open the web UI"
