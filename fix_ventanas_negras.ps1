# fix_ventanas_negras.ps1
# Parchea todos los .py de C:\Titan para suprimir ventanas negras flotantes
# Uso: powershell -ExecutionPolicy Bypass -File fix_ventanas_negras.ps1

$TitanDir = "C:\Titan"
$NO_WIN_DECL = '_NO_WIN = getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)'
$patched = @()

Get-ChildItem -Path $TitanDir -Filter "*.py" -File | ForEach-Object {
    $file = $_.FullName
    $content = Get-Content $file -Raw -Encoding UTF8
    if (-not $content) { return }

    # Solo archivos que usan subprocess
    if ($content -notmatch 'subprocess\.(run|Popen|call)') { return }

    $modified = $false

    # 1. Añadir _NO_WIN si no existe
    if ($content -notmatch '_NO_WIN|CREATE_NO_WINDOW') {
        # Insertar despues del ultimo import subprocess
        $content = $content -replace '(import subprocess[^\n]*\n)', "`$1$NO_WIN_DECL`n"
        $modified = $true
    }

    # 2. Parchear subprocess.run(...) sin creationflags
    $newContent = [System.Text.RegularExpressions.Regex]::Replace(
        $content,
        '(subprocess\.(?:run|Popen|call)\([^)]*?)(\))',
        {
            param($m)
            $inner = $m.Groups[1].Value
            $close = $m.Groups[2].Value
            if ($inner -match 'creationflags|CREATE_NO_WINDOW|NO_WIN') {
                return $m.Value
            }
            $modified = $true
            return "$inner, creationflags=_NO_WIN$close"
        }
    )

    if ($newContent -ne $content) {
        $modified = $true
        $content = $newContent
    }

    if ($modified) {
        [System.IO.File]::WriteAllText($file, $content, [System.Text.Encoding]::UTF8)
        $patched += $_.Name
        Write-Host "PARCHEADO: $($_.Name)" -ForegroundColor Green
    }
}

if ($patched.Count -eq 0) {
    Write-Host "Ningun archivo necesitaba parche." -ForegroundColor Yellow
} else {
    Write-Host "`nArchivos parcheados: $($patched -join ', ')" -ForegroundColor Cyan
}

# Reiniciar procesos pythonw afectados
Write-Host "`nReiniciando procesos pythonw..." -ForegroundColor Yellow
$procs = Get-Process -Name pythonw -ErrorAction SilentlyContinue
foreach ($p in $procs) {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)").CommandLine
        Write-Host "  Matando PID $($p.Id): $cmd" -ForegroundColor Red
        Stop-Process -Id $p.Id -Force
        Start-Sleep -Milliseconds 500
        # Relanzar con pythonw
        if ($cmd -match 'pythonw?\s+"?([^"]+\.py)"?') {
            $script = $matches[1]
            if (Test-Path $script) {
                Start-Process "pythonw" -ArgumentList "`"$script`"" -WorkingDirectory (Split-Path $script)
                Write-Host "  Relanzado: $script" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  Error con PID $($p.Id): $_" -ForegroundColor Red
    }
}

Write-Host "`nListo. Las ventanas negras deben haber desaparecido." -ForegroundColor Green
