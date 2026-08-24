# Reset the Hermes Agent data folder and optionally .env.
#
#   .\reset.ps1          Stop container, clear hermes-data, keep .env
#   .\reset.ps1 -Full    Also delete .env for a complete clean slate
[CmdletBinding()]
param(
    [switch]$Full
)
$ErrorActionPreference = 'Stop'

function Write-Note($msg) { Write-Host $msg -ForegroundColor DarkGray }
function Write-Ok($msg)   { Write-Host "  ok $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "warn $msg" -ForegroundColor Yellow }

function Ask-YesNo($prompt, $default) {
    $hint = if ($default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $val = Read-Host "$prompt $hint"
        if ([string]::IsNullOrWhiteSpace($val)) { $val = $default }
        switch ($val.ToLower()) {
            'y' { return $true }
            'n' { return $false }
            default { Write-Host "Please answer y or n." -ForegroundColor Yellow }
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor White
Write-Host "  Hermes Agent - reset" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White
Write-Host ""

# Determine the data directory from .env if it exists.
$DataDir = './hermes-data'
if (Test-Path .env) {
    $line = Get-Content .env | Where-Object { $_ -match '^HERMES_DATA_DIR=' } | Select-Object -First 1
    if ($line) {
        $val = ($line -replace '^HERMES_DATA_DIR=', '' -replace '"', '').Trim()
        if ($val) { $DataDir = $val }
    }
}

# Stop the container first.
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerCmd) {
    Write-Note 'Stopping Hermes...'
    & docker compose down 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok 'Container stopped' }
    else { Write-Note 'No running container found' }
} else {
    Write-Warn 'Docker not found — skipping container shutdown'
}

Write-Host ""

# Warn about what will be deleted.
if ($Full) {
    Write-Warn 'Full reset: this will delete ALL data AND your .env configuration.'
    Write-Warn "  Data:   $DataDir/*"
    Write-Warn '  Config: .env'
} else {
    Write-Warn "This will delete ALL data in $DataDir/*"
    Write-Note 'Your .env (API keys, provider settings) will be kept.'
}

Write-Host ""
if (-not (Ask-YesNo 'Are you sure? This cannot be undone.' 'n')) {
    Write-Note 'Cancelled. Nothing was changed.'
    Write-Host ""
    exit 0
}

Write-Host ""

# Clear the data directory.
if (Test-Path $DataDir -PathType Container) {
    Get-ChildItem -Path $DataDir -Force | Where-Object { $_.Name -ne '.gitkeep' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Cleared $DataDir"
} else {
    Write-Note "$DataDir does not exist — nothing to clear"
}

# Full reset: also remove .env.
if ($Full -and (Test-Path .env)) {
    Remove-Item .env -Force
    Write-Ok 'Deleted .env'
}

Write-Host ""
if ($Full) {
    Write-Host "Reset complete." -ForegroundColor Green
    Write-Host 'Run .\setup.ps1 to start fresh.' -ForegroundColor White
} else {
    Write-Host "Reset complete." -ForegroundColor Green
    Write-Host 'Your .env is intact — run docker compose up -d to restart.' -ForegroundColor White
    Write-Note 'Or re-run .\setup.ps1 to change your configuration.'
}
Write-Host ""
