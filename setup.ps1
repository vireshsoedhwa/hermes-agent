# Interactive first-run setup for the Hermes Agent Docker deployment.
#
# PowerShell equivalent of setup.sh. Asks the same questions and writes
# the same .env file. Compatible with PowerShell 5.1 (Windows 10/11 default).
#
# Usage:  .\setup.ps1
#         setup.cmd        (dispatcher, bypasses execution policy)
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$EnvFile = '.env'
$ExampleFile = '.env.example'

# ---------------------------------------------------------------------------
# Presentation helpers
# ---------------------------------------------------------------------------
$script:StepNum = 0
$TotalSteps = 6

function Write-Step($title) {
    $script:StepNum++
    Write-Host ""
    Write-Host "[$script:StepNum/$TotalSteps] $title" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------" -ForegroundColor DarkGray
}

function Write-Note($msg) { Write-Host $msg -ForegroundColor DarkGray }
function Write-Ok($msg)   { Write-Host "  ok $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "warn $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "error $msg" -ForegroundColor Red; exit 1 }

function Mask($s) {
    if ($s.Length -le 4) { return '****' }
    return '****' + $s.Substring($s.Length - 4)
}

function Ask-Secret($prompt) {
    $secure = Read-Host -AsSecureString $prompt
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr).Trim()
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Ask-Text($prompt, $default) {
    if ($default) {
        $val = Read-Host "$prompt [$default]"
        if ([string]::IsNullOrWhiteSpace($val)) { return $default }
        return $val.Trim()
    } else {
        return (Read-Host $prompt).Trim()
    }
}

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

function Ask-Choice($max) {
    while ($true) {
        $val = Read-Host "Enter a number [1-$max]"
        $n = 0
        if ([int]::TryParse($val.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $max) {
            return $n
        }
        Write-Host "Please enter a number between 1 and $max." -ForegroundColor Yellow
    }
}

function New-ApiKey {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor White
Write-Host "  Hermes Agent - setup" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White
Write-Note "Answer a few questions and this writes your .env for you."
Write-Note "Press Enter to accept the [default] shown in brackets."

if (-not (Test-Path $ExampleFile)) {
    Write-Err "$ExampleFile not found. Run this from the repository root."
}

$dockerCheck = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCheck) {
    Write-Host ""
    Write-Err 'Docker is required but was not found on your PATH.

    Install Docker Desktop from https://docker.com, then re-run .\setup.cmd'
}

if (Test-Path $EnvFile) {
    Write-Host ""
    Write-Warn "An existing $EnvFile was found."
    if (-not (Ask-YesNo 'Reconfigure from scratch? (a timestamped backup will be kept)' 'n')) {
        Write-Note 'Keeping your existing configuration. Nothing changed.'
        Write-Host ""
        Write-Host 'Start Hermes with: docker compose up -d' -ForegroundColor White
        Write-Host ""
        exit 0
    }
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    $backup = "$EnvFile.backup.$stamp"
    Copy-Item $EnvFile $backup
    Write-Ok "Backed up to $backup"
}

# ---------------------------------------------------------------------------
# Step 1 - LLM provider
# ---------------------------------------------------------------------------
Write-Step 'Choose your AI model provider'
Write-Note 'Hermes needs one provider to think. Ollama Cloud is the easiest start:'
Write-Note 'hosted open models, no GPU required, generous free tier.'
Write-Host ""
Write-Host "  1) Ollama Cloud   hosted open models, no GPU needed" -ForegroundColor White
Write-Host "  2) OpenRouter     one key, 300+ models from every lab" -ForegroundColor White
Write-Host "  3) Anthropic      Claude models, direct" -ForegroundColor White
Write-Host "  4) OpenAI         GPT models, direct" -ForegroundColor White
Write-Host "  5) Google Gemini  free tier available" -ForegroundColor White
Write-Host "  6) Groq           very fast inference" -ForegroundColor White
Write-Host "  7) DeepSeek       low cost" -ForegroundColor White
Write-Host "  8) xAI (Grok)" -ForegroundColor White
Write-Host ""

$choice = Ask-Choice 8

$providers = @{
    1 = @{ Provider='ollama-cloud'; KeyVar='OLLAMA_API_KEY';     KeyUrl='https://ollama.com/settings/keys'
           Models=@('ollama-cloud/gemma4:31b-cloud','ollama-cloud/gpt-oss:120b','ollama-cloud/glm-5.2') }
    2 = @{ Provider='openrouter';   KeyVar='OPENROUTER_API_KEY'; KeyUrl='https://openrouter.ai/keys'
           Models=@('anthropic/claude-sonnet-4.6','openai/gpt-5.5','google/gemini-2.5-flash') }
    3 = @{ Provider='anthropic';    KeyVar='ANTHROPIC_API_KEY';  KeyUrl='https://console.anthropic.com/settings/keys'
           Models=@('claude-sonnet-4-6','claude-opus-4-1','claude-haiku-4-5') }
    4 = @{ Provider='openai';       KeyVar='OPENAI_API_KEY';     KeyUrl='https://platform.openai.com/api-keys'
           Models=@('gpt-5.5','gpt-4o','gpt-4o-mini') }
    5 = @{ Provider='gemini';       KeyVar='GOOGLE_API_KEY';     KeyUrl='https://aistudio.google.com/app/apikey'
           Models=@('gemini-2.5-flash','gemini-2.5-pro','gemini-2.0-flash') }
    6 = @{ Provider='groq';         KeyVar='GROQ_API_KEY';       KeyUrl='https://console.groq.com/keys'
           Models=@('llama-3.3-70b-versatile','moonshotai/kimi-k2-instruct','qwen/qwen3-32b') }
    7 = @{ Provider='deepseek';     KeyVar='DEEPSEEK_API_KEY';   KeyUrl='https://platform.deepseek.com/api_keys'
           Models=@('deepseek-chat','deepseek-reasoner','deepseek-chat') }
    8 = @{ Provider='xai';          KeyVar='XAI_API_KEY';        KeyUrl='https://console.x.ai'
           Models=@('grok-4','grok-3','grok-3-mini') }
}

$p = $providers[$choice]
$PROVIDER   = $p.Provider
$KEY_VAR    = $p.KeyVar
$KEY_URL    = $p.KeyUrl
$MODEL_LIST = $p.Models

Write-Host ""
Write-Note "Get a $KEY_VAR here:"
Write-Host "  $KEY_URL" -ForegroundColor Cyan
Write-Host ""

while ($true) {
    $PROVIDER_KEY = Ask-Secret "Paste your $KEY_VAR (hidden)"
    if ([string]::IsNullOrWhiteSpace($PROVIDER_KEY)) {
        Write-Warn 'A provider key is required - Hermes cannot run without one.'
        continue
    }
    if ($PROVIDER_KEY.Length -lt 8) {
        Write-Warn "That looks too short ($($PROVIDER_KEY.Length) characters). Please check and paste again."
        continue
    }
    break
}
Write-Ok "$KEY_VAR set to $(Mask $PROVIDER_KEY)"

# ---------------------------------------------------------------------------
# Step 2 - Model
# ---------------------------------------------------------------------------
Write-Step 'Pick a default model'
Write-Note "Suggestions for $PROVIDER. You can change this any time with /model in chat."
Write-Host ""
Write-Host "  1) $($MODEL_LIST[0])" -ForegroundColor White
Write-Host "  2) $($MODEL_LIST[1])" -ForegroundColor White
Write-Host "  3) $($MODEL_LIST[2])" -ForegroundColor White
Write-Host "  4) Enter a different model ID" -ForegroundColor DarkGray
Write-Host ""

$choice = Ask-Choice 4
switch ($choice) {
    1 { $MODEL = $MODEL_LIST[0] }
    2 { $MODEL = $MODEL_LIST[1] }
    3 { $MODEL = $MODEL_LIST[2] }
    4 { $MODEL = Ask-Text 'Model ID' $MODEL_LIST[0] }
}
Write-Ok "Default model: $MODEL"

# ---------------------------------------------------------------------------
# Step 3 - API server key
# ---------------------------------------------------------------------------
Write-Step 'API server key'
Write-Note 'Hermes runs an OpenAI-compatible API on port 8642. The dashboard needs'
Write-Note 'it internally, so it always runs — but it binds to 127.0.0.1 by default,'
Write-Note 'meaning external apps cannot reach it. You can optionally expose it.'
Write-Host ""
Write-Note 'A dashboard login password is also generated — the web UI requires'
Write-Note 'auth when binding to 0.0.0.0 (needed for Docker port publishing).'
Write-Host ""

$API_KEY = New-ApiKey
Write-Ok "Generated a $($API_KEY.Length)-character API server key"
Write-Note 'API server is loopback-only (127.0.0.1). The dashboard and CLI work normally.'
Write-Note 'To expose it externally, set HERMES_API_SERVER_HOST=0.0.0.0 in .env.'

$API_HOST = '127.0.0.1'

# Generate a random dashboard password (16 chars, alphanumeric).
$DASH_PASS = -join ((1..16) | ForEach-Object {
    $bytes = New-Object byte[] 1
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    $b = $bytes[0] % 62
    if ($b -lt 10) { [char]($b + 48) }
    elseif ($b -lt 36) { [char]($b + 55) }
    else { [char]($b + 61) }
})
Write-Ok "Generated dashboard password: $DASH_PASS"
Write-Note 'You will need this to log in at http://localhost:9119'
Write-Note 'Re-run setup to regenerate it.'

# ---------------------------------------------------------------------------
# Step 4 - Web search (optional)
# ---------------------------------------------------------------------------
Write-Step 'Web search (optional)'
Write-Note 'Without this the agent cannot look things up online. Brave has a free tier.'
Write-Host ""
Write-Host "  1) Brave Search   free tier - recommended" -ForegroundColor White
Write-Host "  2) Tavily         built for LLMs" -ForegroundColor White
Write-Host "  3) Exa            semantic search" -ForegroundColor White
Write-Host "  4) Skip for now" -ForegroundColor DarkGray
Write-Host ""

$choice = Ask-Choice 4

$SEARCH_VAR = ''
$SEARCH_KEY = ''
$SEARCH_URL = ''
switch ($choice) {
    1 { $SEARCH_VAR = 'BRAVE_SEARCH_API_KEY'; $SEARCH_URL = 'https://brave.com/search/api/' }
    2 { $SEARCH_VAR = 'TAVILY_API_KEY';       $SEARCH_URL = 'https://app.tavily.com/home' }
    3 { $SEARCH_VAR = 'EXA_API_KEY';          $SEARCH_URL = 'https://exa.ai' }
    4 { Write-Note 'Skipped. Add a search key later by re-running setup.' }
}

if ($SEARCH_VAR) {
    Write-Host ""
    Write-Note "Get a $SEARCH_VAR here:"
    Write-Host "  $SEARCH_URL" -ForegroundColor Cyan
    Write-Host ""
    $SEARCH_KEY = Ask-Secret "Paste your $SEARCH_VAR (hidden, Enter to skip)"
    if ($SEARCH_KEY) {
        Write-Ok "$SEARCH_VAR set to $(Mask $SEARCH_KEY)"
    } else {
        Write-Note 'Skipped.'
        $SEARCH_VAR = ''
    }
}

# ---------------------------------------------------------------------------
# Step 5 - Chat platform (optional)
# ---------------------------------------------------------------------------
Write-Step 'Chat platform (optional)'
Write-Note 'Message Hermes from your phone. You can always use the web dashboard instead.'
Write-Host ""
Write-Host "  1) Telegram  create a bot with @BotFather" -ForegroundColor White
Write-Host "  2) Discord" -ForegroundColor White
Write-Host "  3) Slack" -ForegroundColor White
Write-Host "  4) Skip - use the dashboard at localhost:9119" -ForegroundColor DarkGray
Write-Host ""

$choice = Ask-Choice 4

$CHAT_VAR = ''
$CHAT_KEY = ''
$CHAT_URL = ''
switch ($choice) {
    1 { $CHAT_VAR = 'TELEGRAM_BOT_TOKEN'; $CHAT_URL = 'https://t.me/BotFather' }
    2 { $CHAT_VAR = 'DISCORD_BOT_TOKEN';  $CHAT_URL = 'https://discord.com/developers/applications' }
    3 { $CHAT_VAR = 'SLACK_BOT_TOKEN';    $CHAT_URL = 'https://api.slack.com/apps' }
    4 { Write-Note 'Skipped. The web dashboard and API server are always available.' }
}

if ($CHAT_VAR) {
    Write-Host ""
    Write-Note "Create your bot and get a $CHAT_VAR here:"
    Write-Host "  $CHAT_URL" -ForegroundColor Cyan
    Write-Host ""
    $CHAT_KEY = Ask-Secret "Paste your $CHAT_VAR (hidden, Enter to skip)"
    if ($CHAT_KEY) {
        Write-Ok "$CHAT_VAR set to $(Mask $CHAT_KEY)"
    } else {
        Write-Note 'Skipped.'
        $CHAT_VAR = ''
    }
}

# ---------------------------------------------------------------------------
# Step 6 - Data folder
# ---------------------------------------------------------------------------
Write-Step 'Where should Hermes keep its data?'
Write-Note 'One folder holds everything: config, chat history, memory, learned skills'
Write-Note 'and logs. Back up this folder and you have backed up your whole agent.'
Write-Host ""

$DATA_DIR = Ask-Text 'Data folder' './hermes-data'

if (-not (Test-Path $DATA_DIR -PathType Container)) {
    if (Ask-YesNo "$DATA_DIR does not exist. Create it?" 'y') {
        New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null
        Write-Ok "Created $DATA_DIR"
    }
} else {
    Write-Ok "Using $DATA_DIR"
}

# Windows: Docker Desktop handles file permissions, so no UID/GID needed.

# ---------------------------------------------------------------------------
# Write dashboard basic_auth into config.yaml
# ---------------------------------------------------------------------------
# The dashboard refuses to bind to 0.0.0.0 without an auth provider.
# We generate a scrypt hash using the Hermes container's Python and inject
# it into config.yaml so the dashboard starts cleanly on first boot.
$CONFIG_FILE = Join-Path $DATA_DIR 'config.yaml'
$dockerCheck = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerCheck) {
    Write-Note 'Generating dashboard password hash...'
    $pyCode = "from plugins.dashboard_auth.basic import hash_password; print(hash_password('$DASH_PASS'))"
    $DASH_HASH = (docker run --rm --entrypoint python nousresearch/hermes-agent:latest -c $pyCode 2>$null)
    if ($DASH_HASH) {
        if (Test-Path $CONFIG_FILE) {
            $lines = Get-Content $CONFIG_FILE
            $skip = $false
            $filtered = @()
            foreach ($line in $lines) {
                if ($line -match '^dashboard:') { $skip = $true; continue }
                if ($skip -and ($line -match '^[^ #]')) { $skip = $false }
                if (-not $skip) { $filtered += $line }
            }
            $filtered | Set-Content $CONFIG_FILE -Encoding UTF8
        }
        $authBlock = "`ndashboard:`n  basic_auth:`n    username: admin`n    password_hash: `"$DASH_HASH`"`n"
        Add-Content -Path $CONFIG_FILE -Value $authBlock -Encoding UTF8
        Write-Ok 'Dashboard auth configured in config.yaml'
    } else {
        Write-Warn 'Could not generate password hash (Docker failed).'
        Write-Warn "Add this to $CONFIG_FILE manually:"
        Write-Host '  dashboard:'
        Write-Host '    basic_auth:'
        Write-Host '      username: admin'
        Write-Host "      password_hash: <run docker to generate hash for password: $DASH_PASS>"
    }
} else {
    Write-Warn 'Docker not found — cannot generate dashboard password hash.'
    Write-Warn "After installing Docker, run setup again, or manually add to $CONFIG_FILE:"
    Write-Host '  dashboard:'
    Write-Host '    basic_auth:'
    Write-Host '      username: admin'
    Write-Host '      password_hash: <generated by Hermes container>'
}

# ---------------------------------------------------------------------------
# Write .env
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--------------------------------------------------------------" -ForegroundColor DarkGray

function EmitKey($sb, $var, $val) {
    [void]$sb.AppendLine("$var=$val")
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Generated by setup.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("# Re-run setup at any time to change these answers.")
[void]$sb.AppendLine("# Reference for every supported option: .env.example")
[void]$sb.AppendLine("")

[void]$sb.AppendLine("# --- API server (OpenAI-compatible endpoint on port 8642) -----------")
[void]$sb.AppendLine("# Loopback by default. Set HERMES_API_SERVER_HOST=0.0.0.0 to expose.")
EmitKey $sb 'HERMES_API_SERVER_HOST' $API_HOST
EmitKey $sb 'HERMES_API_SERVER_KEY' $API_KEY
[void]$sb.AppendLine("")

[void]$sb.AppendLine("# --- Model ----------------------------------------------------------")
EmitKey $sb 'HERMES_INFERENCE_PROVIDER' $PROVIDER
EmitKey $sb 'HERMES_DEFAULT_MODEL' $MODEL
[void]$sb.AppendLine("")

[void]$sb.AppendLine("# --- Provider credentials -------------------------------------------")
$allKeys = @('OLLAMA_API_KEY','OPENROUTER_API_KEY','ANTHROPIC_API_KEY','OPENAI_API_KEY',
             'GOOGLE_API_KEY','GROQ_API_KEY','DEEPSEEK_API_KEY','XAI_API_KEY')
foreach ($v in $allKeys) {
    if ($v -eq $KEY_VAR) { EmitKey $sb $v $PROVIDER_KEY }
    else { EmitKey $sb $v '' }
}
[void]$sb.AppendLine("")

[void]$sb.AppendLine("# --- Web search -----------------------------------------------------")
$allSearch = @('BRAVE_SEARCH_API_KEY','TAVILY_API_KEY','EXA_API_KEY')
foreach ($v in $allSearch) {
    if ($v -eq $SEARCH_VAR) { EmitKey $sb $v $SEARCH_KEY }
    else { EmitKey $sb $v '' }
}
[void]$sb.AppendLine("")

[void]$sb.AppendLine("# --- Chat platforms -------------------------------------------------")
$allChat = @('TELEGRAM_BOT_TOKEN','DISCORD_BOT_TOKEN','SLACK_BOT_TOKEN')
foreach ($v in $allChat) {
    if ($v -eq $CHAT_VAR) { EmitKey $sb $v $CHAT_KEY }
    else { EmitKey $sb $v '' }
}
[void]$sb.AppendLine("")

[void]$sb.AppendLine("# --- Voice / transcription (optional) -------------------------------")
EmitKey $sb 'ELEVENLABS_API_KEY' ''
[void]$sb.AppendLine("")

[void]$sb.AppendLine("# --- Storage --------------------------------------------------------")
EmitKey $sb 'HERMES_DATA_DIR' $DATA_DIR
[void]$sb.AppendLine("")

[void]$sb.AppendLine("# --- Linux file ownership (not needed on Windows) -------------------")
[void]$sb.AppendLine("# HERMES_UID=1000")
[void]$sb.AppendLine("# HERMES_GID=1000")

$sb.ToString() | Set-Content -Path $EnvFile -Encoding ASCII -NoNewline

# Restrict .env to current user only (Windows equivalent of chmod 600).
try {
    & icacls $EnvFile /inheritance:r /grant:r "$env:USERNAME:F" 2>&1 | Out-Null
    Write-Ok "Wrote $EnvFile (access restricted to current user, gitignored)"
} catch {
    Write-Ok "Wrote $EnvFile (gitignored)"
}

# ---------------------------------------------------------------------------
# Summary and launch
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor White
Write-Host "  Setup complete" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor White
Write-Host ""
Write-Host "  Provider     $PROVIDER"
Write-Host "  Model        $MODEL"
if ($API_HOST -eq '0.0.0.0') {
    Write-Host "  API server   port 8642 (external)"
} else {
    Write-Host "  API server   port 8642 (loopback only)"
}
Write-Host "  Dashboard   http://localhost:9119" -ForegroundColor Cyan
Write-Host "  Login       admin / $DASH_PASS" -ForegroundColor White
Write-Host "  Web search   $(if ($SEARCH_VAR) { $SEARCH_VAR } else { 'none' })"
Write-Host "  Chat         $(if ($CHAT_VAR) { $CHAT_VAR } else { 'dashboard only' })"
Write-Host "  Data folder  $DATA_DIR"

Write-Host ""
if (Ask-YesNo 'Start Hermes now?' 'y') {
    Write-Host ""
    Write-Note 'Running: docker compose up -d'
    Write-Host ""
    & docker compose up -d
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Hermes is starting." -ForegroundColor Green
        Write-Host ""
        Write-Host "  Dashboard  http://localhost:9119" -ForegroundColor Cyan
        Write-Host "  Login      admin / $DASH_PASS" -ForegroundColor White
        if ($API_HOST -eq '0.0.0.0') {
            Write-Host "  API        http://localhost:8642/v1" -ForegroundColor Cyan
        }
        Write-Host "  Logs       docker compose logs -f"
        Write-Host "  Terminal   docker exec -it hermes hermes"
        Write-Host ""
    } else {
        Write-Host ""
        Write-Err 'Startup failed. Read the preflight output above, then re-run setup or docker compose up -d'
    }
} else {
    Write-Host ""
    Write-Host 'Start it whenever you are ready: docker compose up -d' -ForegroundColor White
    Write-Host ""
}
