# arrancar_litellm.ps1
# Arranca LiteLLM proxy con fallback automatico a Ollama local
# Uso: irm https://raw.githubusercontent.com/Yomismosoychat/pizarra-juridico/claude/compact-mode-rbttdt/arrancar_litellm.ps1 | iex

$TitanDir = "C:\Titan"
$ConfigPath = "$TitanDir\litellm_config.yaml"
$LogPath = "$TitanDir\logs\litellm.log"

# Crear directorio logs si no existe
if (-not (Test-Path "$TitanDir\logs")) {
    New-Item -ItemType Directory -Path "$TitanDir\logs" | Out-Null
}

# Escribir config de LiteLLM
$config = @"
model_list:
  - model_name: claude
    litellm_params:
      model: anthropic/claude-opus-4-5
      api_key: os.environ/ANTHROPIC_API_KEY
  - model_name: claude
    litellm_params:
      model: ollama/qwen2.5:3b
      api_base: http://localhost:11434
  - model_name: claude
    litellm_params:
      model: ollama/deepseek-r1:1.5b
      api_base: http://localhost:11434

router_settings:
  routing_strategy: least-busy
  num_retries: 2
  fallbacks:
    - {"claude": ["ollama/qwen2.5:3b", "ollama/deepseek-r1:1.5b"]}
  context_window_fallbacks:
    - {"claude": ["ollama/qwen2.5:3b"]}
  allowed_fails: 1

litellm_settings:
  drop_params: true
  success_callback: []
  failure_callback: []

general_settings:
  master_key: "titan-local-key"
  port: 4000
"@

[System.IO.File]::WriteAllText($ConfigPath, $config, [System.Text.Encoding]::UTF8)
Write-Host "Config escrita en $ConfigPath" -ForegroundColor Green

# Verificar que litellm esta instalado
$litellmOk = $false
try {
    $ver = & python -m litellm --version 2>&1
    if ($LASTEXITCODE -eq 0 -or $ver -match '\d') {
        $litellmOk = $true
        Write-Host "LiteLLM instalado: $ver" -ForegroundColor Green
    }
} catch {}

if (-not $litellmOk) {
    Write-Host "Instalando LiteLLM..." -ForegroundColor Yellow
    & pip install litellm[proxy] --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: No se pudo instalar litellm. Prueba manualmente: pip install litellm[proxy]" -ForegroundColor Red
        exit 1
    }
}

# Matar instancia anterior si existe
Get-Process | Where-Object { $_.Name -match "litellm" } | Stop-Process -Force -ErrorAction SilentlyContinue

# Arrancar LiteLLM en background sin ventana
$NO_WIN = 0x08000000
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "python"
$psi.Arguments = "-m litellm --config `"$ConfigPath`" --port 4000"
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.WorkingDirectory = $TitanDir
$p = [System.Diagnostics.Process]::Start($psi)

Write-Host "LiteLLM arrancando (PID $($p.Id))..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verificar que responde
try {
    $resp = Invoke-WebRequest "http://127.0.0.1:4000/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "LiteLLM ACTIVO en http://127.0.0.1:4000 (status $($resp.StatusCode))" -ForegroundColor Green
    Write-Host ""
    Write-Host "Antigravity debe apuntar a: http://127.0.0.1:4000" -ForegroundColor Cyan
    Write-Host "API Key para Antigravity:    titan-local-key" -ForegroundColor Cyan
    Write-Host "Fallback automatico:         qwen2.5:3b -> deepseek-r1:1.5b" -ForegroundColor Cyan
} catch {
    Write-Host "LiteLLM no responde aun. Espera 10s y prueba: curl http://127.0.0.1:4000/health" -ForegroundColor Yellow
    Write-Host "Log en: $LogPath" -ForegroundColor Yellow
}
