# instalar_litellm_autostart.ps1
# Instala LiteLLM como tarea de inicio automatico de Windows
# UNA SOLA VEZ. Luego arranca solo en cada reinicio.

$TitanDir = "C:\Titan"
$LitellmExe = "$env:APPDATA\Python\Python314\Scripts\litellm.exe"
$ConfigPath = "$TitanDir\litellm_config.yaml"
$LogPath = "$TitanDir\logs\litellm.log"
$TaskName = "TITAN_LiteLLM_Proxy"

# Escribir config
if (-not (Test-Path "$TitanDir\logs")) { New-Item -ItemType Directory "$TitanDir\logs" | Out-Null }

@"
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
  num_retries: 2
  fallbacks:
    - {"claude": ["ollama/qwen2.5:3b", "ollama/deepseek-r1:1.5b"]}
  allowed_fails: 1

litellm_settings:
  drop_params: true

general_settings:
  master_key: "titan-local-key"
  port: 4000
"@ | Set-Content $ConfigPath -Encoding UTF8

# Crear wrapper .bat sin ventana
$batPath = "$TitanDir\start_litellm.bat"
@"
@echo off
"$LitellmExe" --config "$ConfigPath" --port 4000 >> "$LogPath" 2>&1
"@ | Set-Content $batPath -Encoding ASCII

# Registrar tarea programada de inicio
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batPath`"" -WorkingDirectory $TitanDir
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

# Eliminar tarea anterior si existe
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Tarea '$TaskName' registrada. Arrancara en cada inicio de sesion." -ForegroundColor Green

# Arrancar ahora mismo
Write-Host "Arrancando LiteLLM ahora..." -ForegroundColor Yellow
Stop-Process -Name "litellm*" -Force -ErrorAction SilentlyContinue
Start-Process "cmd.exe" -ArgumentList "/c `"$batPath`"" -WindowStyle Hidden -WorkingDirectory $TitanDir
Start-Sleep -Seconds 12

# Verificar
$port = 4000
try {
    $r = Invoke-WebRequest "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "LITELLM ACTIVO en puerto $port (HTTP $($r.StatusCode))" -ForegroundColor Green
    Write-Host ""
    Write-Host "Antigravity debe apuntar a:" -ForegroundColor Cyan
    Write-Host "  Base URL: http://127.0.0.1:4000" -ForegroundColor White
    Write-Host "  API Key:  titan-local-key" -ForegroundColor White
    Write-Host "  Fallback: qwen2.5:3b -> deepseek-r1:1.5b (automatico, coste 0)" -ForegroundColor White
} catch {
    # Puede que haya elegido otro puerto - buscar en log
    $logContent = Get-Content $LogPath -ErrorAction SilentlyContinue | Select-Object -Last 5
    Write-Host "Puerto 4000 no responde. Log:" -ForegroundColor Yellow
    $logContent | ForEach-Object { Write-Host "  $_" }
}
