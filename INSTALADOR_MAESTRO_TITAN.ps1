# =====================================================================
# INSTALADOR_MAESTRO_TITAN.ps1 — Despliegue en 1 clic
# Sistema TITAN · 2026-10-23 · Ejecutar como Administrador
# =====================================================================
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$TitanRoot  = "C:\Titan"
$PgUser     = "titan_local"
$PgDb       = "titan_local"
$PgContainer = "titan-postgres"
$McpContainer = "titan-fastmcp"

function Log($msg) { Write-Host "[TITAN] $msg" -ForegroundColor Cyan }
function OK($msg)  { Write-Host "[  OK ] $msg" -ForegroundColor Green }
function ERR($msg) { Write-Host "[ ERR ] $msg" -ForegroundColor Red }

# ─────────────────────────────────────────────────────────────────────
# PASO 1 — LIMPIEZA DE PROCESOS ANTIGRAVITY
# ─────────────────────────────────────────────────────────────────────
Log "Paso 1: Cerrando procesos Antigravity residuales..."

$agNames = @("antigravity", "Antigravity", "claude-cowork", "cowork", "electron")
foreach ($name in $agNames) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force
        OK "Proceso '$name' terminado ($($procs.Count) instancia/s)."
    }
}

# Matar cualquier ventana flotante sin título (cuota agotada)
Get-Process | Where-Object {
    $_.MainWindowTitle -match "quota|cuota|agotad|claude|cowork" -and $_.MainWindowTitle -ne ""
} | ForEach-Object {
    $_ | Stop-Process -Force
    OK "Ventana flotante cerrada: $($_.MainWindowTitle)"
}
OK "Limpieza de procesos completada."


# ─────────────────────────────────────────────────────────────────────
# PASO 2 — CREAR DIRECTORIO C:\Titan\
# ─────────────────────────────────────────────────────────────────────
Log "Paso 2: Verificando directorio $TitanRoot..."
if (-not (Test-Path $TitanRoot)) {
    New-Item -ItemType Directory -Path $TitanRoot | Out-Null
    OK "Directorio $TitanRoot creado."
} else {
    OK "$TitanRoot ya existe."
}


# ─────────────────────────────────────────────────────────────────────
# PASO 3 — ESCRIBIR server.py (FastMCP, puerto 18080)
# ─────────────────────────────────────────────────────────────────────
Log "Paso 3: Escribiendo C:\Titan\server.py..."

$serverPy = @'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
server.py — FastMCP TITAN Core   puerto 18080
Endpoints: registrar_actuacion | actualizar_expediente |
           crear_tarea_seguimiento | sincronizar_pizarra
"""
import json, datetime, os
import psycopg2
from psycopg2.extras import RealDictCursor
from pydantic import BaseModel, Field
from typing import Optional
from fastmcp import FastMCP

# ── Conexión PostgreSQL ─────────────────────────────────────────────
DB_DSN = os.getenv(
    "TITAN_DB_DSN",
    "postgresql://titan_local:titan_local@localhost:5432/titan_local"
)

def get_conn():
    return psycopg2.connect(DB_DSN)

# ── Servidor FastMCP ────────────────────────────────────────────────
mcp = FastMCP("TITAN-Core")


# ── Modelos Pydantic ────────────────────────────────────────────────
class ActuacionInput(BaseModel):
    codigo_expediente: str
    tipo: str                         # p.ej. EVACUACION, PAGO, ALERTA_DEHU, etc.
    descripcion: str
    fecha: Optional[str] = None       # YYYY-MM-DD
    drive_url: Optional[str] = None
    alerta: Optional[str] = None

class ExpedienteUpdate(BaseModel):
    codigo_expediente: str
    estado: Optional[str] = None
    prioridad: Optional[str] = None   # ROJO | NARANJA | AMARILLO | VERDE | BLANCO
    proxima_actuacion: Optional[str] = None
    fecha_limite: Optional[str] = None
    c_trial: Optional[str] = None
    c_nextDate: Optional[str] = None
    alerta: Optional[str] = None

class TareaInput(BaseModel):
    codigo_expediente: str
    descripcion: str
    fecha_vencimiento: Optional[str] = None
    prioridad: Optional[str] = "MEDIA"

class SincronizarInput(BaseModel):
    forzar: bool = False


# ── Tool 1: registrar_actuacion ─────────────────────────────────────
@mcp.tool()
def registrar_actuacion(data: ActuacionInput) -> dict:
    """Inserta una actuación procesal en PostgreSQL."""
    with get_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT id FROM expedientes
                WHERE codigo = %s
            """, (data.codigo_expediente,))
            row = cur.fetchone()
            if not row:
                return {"ok": False, "error": f"Expediente '{data.codigo_expediente}' no encontrado."}
            exp_id = row["id"]

            cur.execute("""
                INSERT INTO actuaciones
                    (expediente_id, tipo, descripcion, fecha, drive_url, alerta, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, NOW())
                RETURNING id
            """, (
                exp_id, data.tipo, data.descripcion,
                data.fecha or datetime.date.today().isoformat(),
                data.drive_url, data.alerta
            ))
            act_id = cur.fetchone()["id"]
            conn.commit()
    return {"ok": True, "actuacion_id": act_id, "expediente": data.codigo_expediente}


# ── Tool 2: actualizar_expediente ───────────────────────────────────
@mcp.tool()
def actualizar_expediente(data: ExpedienteUpdate) -> dict:
    """Upsert de campos del expediente en PostgreSQL."""
    fields, values = [], []
    for col in ("estado","prioridad","proxima_actuacion",
                "fecha_limite","c_trial","c_nextDate","alerta"):
        val = getattr(data, col)
        if val is not None:
            fields.append(f"{col} = %s")
            values.append(val)
    if not fields:
        return {"ok": False, "error": "Ningún campo para actualizar."}

    values.append(data.codigo_expediente)
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                f"UPDATE expedientes SET {', '.join(fields)}, updated_at = NOW() "
                f"WHERE codigo = %s",
                values
            )
            updated = cur.rowcount
            conn.commit()
    if updated == 0:
        return {"ok": False, "error": f"Expediente '{data.codigo_expediente}' no encontrado."}
    return {"ok": True, "updated": updated, "expediente": data.codigo_expediente}


# ── Tool 3: crear_tarea_seguimiento ────────────────────────────────
@mcp.tool()
def crear_tarea_seguimiento(data: TareaInput) -> dict:
    """Crea una tarea de seguimiento vinculada al expediente."""
    with get_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM expedientes WHERE codigo = %s",
                        (data.codigo_expediente,))
            row = cur.fetchone()
            if not row:
                return {"ok": False, "error": f"Expediente '{data.codigo_expediente}' no encontrado."}
            cur.execute("""
                INSERT INTO tareas
                    (expediente_id, descripcion, fecha_vencimiento, prioridad, estado, created_at)
                VALUES (%s, %s, %s, %s, 'PENDIENTE', NOW())
                RETURNING id
            """, (row["id"], data.descripcion, data.fecha_vencimiento, data.prioridad))
            tarea_id = cur.fetchone()["id"]
            conn.commit()
    return {"ok": True, "tarea_id": tarea_id}


# ── Tool 4: sincronizar_pizarra ─────────────────────────────────────
@mcp.tool()
def sincronizar_pizarra(data: SincronizarInput) -> dict:
    """Dispara la regeneración de PIZARRA_TITAN.html desde PostgreSQL."""
    import subprocess, sys
    script = r"C:\Titan\titan_pizarra_server.py"
    if not os.path.exists(script):
        return {"ok": False, "error": "titan_pizarra_server.py no encontrado."}
    try:
        result = subprocess.run(
            [sys.executable, script, "--regenerate-only"],
            capture_output=True, text=True, timeout=10
        )
        return {"ok": result.returncode == 0,
                "stdout": result.stdout[:500],
                "stderr": result.stderr[:200]}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ── Tool extra: system_status ───────────────────────────────────────
@mcp.tool()
def system_status() -> dict:
    """Devuelve el estado operativo del sistema TITAN."""
    try:
        with get_conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT prioridad, COUNT(*) AS total
                    FROM expedientes GROUP BY prioridad ORDER BY prioridad
                """)
                censo = {r["prioridad"]: r["total"] for r in cur.fetchall()}
                cur.execute("SELECT COUNT(*) AS total FROM actuaciones")
                acts = cur.fetchone()["total"]
        db_ok = True
    except Exception as e:
        censo, acts, db_ok = {}, 0, False

    return {
        "ok": True,
        "db_connected": db_ok,
        "censo_expedientes": censo,
        "total_actuaciones": acts,
        "timestamp": datetime.datetime.now().isoformat()
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(mcp.app, host="0.0.0.0", port=18080)
'@

Set-Content -Path "$TitanRoot\server.py" -Value $serverPy -Encoding UTF8
OK "server.py escrito."


# ─────────────────────────────────────────────────────────────────────
# PASO 4 — ESCRIBIR titan_pizarra_server.py (HTTP, puerto 8765)
# ─────────────────────────────────────────────────────────────────────
Log "Paso 4: Escribiendo C:\Titan\titan_pizarra_server.py..."

$pizarraServerPy = @'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
titan_pizarra_server.py — Servidor HTTP local TITAN (puerto 8765)
Regenera PIZARRA_TITAN.html desde PostgreSQL cada 2.5 segundos.
Flags: --regenerate-only (genera HTML y sale sin servir)
"""
import sys, os, json, time, threading, datetime, pathlib
import http.server, socketserver
import psycopg2
from psycopg2.extras import RealDictCursor

PORT = 8765
HTML_PATH = pathlib.Path(r"C:\Titan\PIZARRA_TITAN.html")
DB_DSN    = os.getenv("TITAN_DB_DSN",
    "postgresql://titan_local:titan_local@localhost:5432/titan_local")

PRIORIDAD_COLOR = {
    "ROJO":    "#E53935",
    "NARANJA": "#FB8C00",
    "AMARILLO":"#FDD835",
    "VERDE":   "#43A047",
    "BLANCO":  "#BDBDBD",
}

PRIORIDAD_ORDER = {"ROJO":0,"NARANJA":1,"AMARILLO":2,"VERDE":3,"BLANCO":4}


def fetch_expedientes():
    with psycopg2.connect(DB_DSN) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT e.codigo, e.nombre, e.jurisdiccion, e.organo,
                       e.referencia, e.estado, e.prioridad,
                       e.proxima_actuacion, e.fecha_limite,
                       e.c_trial, e.alerta, e.updated_at,
                       (SELECT COUNT(*) FROM actuaciones a
                        WHERE a.expediente_id = e.id) AS n_actuaciones
                FROM expedientes e
                ORDER BY
                    CASE e.prioridad
                        WHEN 'ROJO'    THEN 0
                        WHEN 'NARANJA' THEN 1
                        WHEN 'AMARILLO'THEN 2
                        WHEN 'VERDE'   THEN 3
                        ELSE 4
                    END,
                    e.fecha_limite ASC NULLS LAST,
                    e.codigo ASC
            """)
            return cur.fetchall()


def badge(prioridad):
    color = PRIORIDAD_COLOR.get(prioridad, "#9E9E9E")
    return (f'<span style="background:{color};color:#fff;padding:2px 8px;'
            f'border-radius:4px;font-size:11px;font-weight:700;">{prioridad}</span>')


def render_card(e):
    bg      = PRIORIDAD_COLOR.get(e["prioridad"], "#9E9E9E") + "22"
    border  = PRIORIDAD_COLOR.get(e["prioridad"], "#9E9E9E")
    fl      = e["fecha_limite"] or "—"
    trial   = e["c_trial"]      or "—"
    alerta  = f'<div class="alerta">⚠ {e["alerta"]}</div>' if e["alerta"] else ""
    prox    = e["proxima_actuacion"] or ""
    updated = str(e["updated_at"])[:16] if e["updated_at"] else ""
    return f"""
    <div class="card" style="background:{bg};border-left:4px solid {border}">
      <div class="card-header">
        <span class="codigo">{e['codigo']}</span>
        {badge(e['prioridad'])}
        <span class="estado">{e['estado'] or ''}</span>
      </div>
      <div class="nombre">{e['nombre'] or ''}</div>
      <div class="meta">
        <span>{e['jurisdiccion'] or ''}</span>
        <span>{e['organo'] or ''}</span>
        <span class="ref">{e['referencia'] or ''}</span>
      </div>
      {alerta}
      <div class="fechas">
        <span>Límite: <b>{fl}</b></span>
        <span>Juicio: <b>{trial}</b></span>
        <span>Acts: {e['n_actuaciones']}</span>
      </div>
      {"<div class='prox'>" + prox + "</div>" if prox else ""}
      <div class="updated">Actualizado: {updated}</div>
    </div>"""


def generate_html(expedientes):
    ahora = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    censo = {}
    for e in expedientes:
        p = e["prioridad"] or "BLANCO"
        censo[p] = censo.get(p, 0) + 1

    stats = " · ".join(
        f'<span style="color:{PRIORIDAD_COLOR.get(p,"#999")}">'
        f'<b>{p}={censo[p]}</b></span>'
        for p in ["ROJO","NARANJA","AMARILLO","VERDE","BLANCO"] if p in censo
    )

    cards = "\n".join(render_card(e) for e in expedientes)
    total = len(expedientes)

    return f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PIZARRA TITÁN — {ahora}</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: 'Segoe UI', sans-serif; background: #1a1a2e; color: #e0e0e0;
          padding: 16px; }}
  h1   {{ font-size: 20px; color: #90CAF9; margin-bottom: 6px; }}
  .stats  {{ font-size: 13px; margin-bottom: 16px; }}
  .grid   {{ display: grid;
             grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
             gap: 12px; }}
  .card   {{ border-radius: 8px; padding: 12px; font-size: 13px; }}
  .card-header {{ display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }}
  .codigo {{ font-weight: 700; font-size: 14px; color: #fff; }}
  .estado {{ font-size: 11px; color: #aaa; margin-left: auto; }}
  .nombre {{ font-size: 13px; margin: 4px 0; }}
  .meta   {{ font-size: 11px; color: #aaa; display: flex; gap: 8px; flex-wrap: wrap; }}
  .ref    {{ font-style: italic; }}
  .alerta {{ background: #B71C1C; color: #fff; font-size: 11px;
              padding: 2px 6px; border-radius: 3px; margin: 4px 0; }}
  .fechas {{ font-size: 11px; margin-top: 6px; display: flex; gap: 10px; }}
  .prox   {{ font-size: 11px; color: #ccc; margin-top: 4px;
              border-top: 1px solid #ffffff22; padding-top: 4px; }}
  .updated {{ font-size: 10px; color: #666; margin-top: 4px; text-align: right; }}
  .footer  {{ margin-top: 20px; font-size: 11px; color: #555; text-align: center; }}
</style>
</head>
<body>
<h1>⚖ PIZARRA TITÁN — {total} expedientes</h1>
<div class="stats">{stats} &nbsp;·&nbsp; {ahora}</div>
<div class="grid">
{cards}
</div>
<div class="footer">Regenerado automáticamente por titan_pizarra_server.py · {ahora}</div>
<script>setTimeout(()=>location.reload(), 10000);</script>
</body>
</html>"""


def regenerate():
    try:
        exps = fetch_expedientes()
        html = generate_html(exps)
        HTML_PATH.write_text(html, encoding="utf-8")
        return True
    except Exception as ex:
        print(f"[PIZARRA] Error regenerando: {ex}", flush=True)
        return False


class ActuacionesEventDaemon(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True, name="ActuacionesEventDaemon")
        self._last_count = -1

    def run(self):
        print("[DAEMON] Iniciado — polling PostgreSQL cada 2.5s", flush=True)
        while True:
            try:
                with psycopg2.connect(DB_DSN) as conn:
                    with conn.cursor() as cur:
                        cur.execute("SELECT COUNT(*) FROM actuaciones")
                        n = cur.fetchone()[0]
                if n != self._last_count:
                    t0 = time.time()
                    regenerate()
                    ms = int((time.time() - t0) * 1000)
                    self._last_count = n
                    print(f"[DAEMON] HTML regenerado en {ms}ms ({n} actuaciones)", flush=True)
            except Exception as ex:
                print(f"[DAEMON] Error: {ex}", flush=True)
            time.sleep(2.5)


class PizarraHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/index.html", "/PIZARRA_TITAN.html"):
            if HTML_PATH.exists():
                data = HTML_PATH.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", len(data))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_error(503, "HTML no generado todavía.")
        else:
            super().do_GET()

    def log_message(self, fmt, *args):
        pass  # silenciar logs HTTP


if __name__ == "__main__":
    regen_only = "--regenerate-only" in sys.argv

    print("[TITAN] Generando HTML inicial...", flush=True)
    ok = regenerate()
    if regen_only:
        sys.exit(0 if ok else 1)

    daemon = ActuacionesEventDaemon()
    daemon.start()

    os.chdir(str(HTML_PATH.parent))
    with socketserver.TCPServer(("127.0.0.1", PORT), PizarraHandler) as httpd:
        print(f"[TITAN] Pizarra disponible en http://127.0.0.1:{PORT}/", flush=True)
        httpd.serve_forever()
'@

Set-Content -Path "$TitanRoot\titan_pizarra_server.py" -Value $pizarraServerPy -Encoding UTF8
OK "titan_pizarra_server.py escrito."


# ─────────────────────────────────────────────────────────────────────
# PASO 5 — INYECTAR TRIGGER PostgreSQL VÍA DOCKER
# ─────────────────────────────────────────────────────────────────────
Log "Paso 5: Inyectando trigger en PostgreSQL via docker exec..."

$triggerSQL = @'
-- ── Función de mutación automática ──────────────────────────────────
CREATE OR REPLACE FUNCTION fn_actuaciones_mutacion_automatica()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_exp_id  INTEGER;
    v_prioridad TEXT;
BEGIN
    v_exp_id := NEW.expediente_id;

    -- Solo actúa sobre tipos de evacuación/resolución
    IF NEW.tipo IN (
        'EVACUACION','PAGO','SUBSANACION','RECURSO',
        'SENTENCIA_FAVORABLE','AUTO_ARCHIVO','DECRETO_ADMISION',
        'RESOLUCION_JUDICIAL','DILIGENCIA_POSITIVA'
    ) THEN
        -- Leer prioridad actual
        SELECT prioridad INTO v_prioridad
        FROM expedientes WHERE id = v_exp_id;

        -- Solo muta si estaba en ROJO o NARANJA
        IF v_prioridad IN ('ROJO','NARANJA') THEN
            UPDATE expedientes
            SET prioridad   = 'AMARILLO',
                estado      = 'JUZGADO',
                updated_at  = NOW()
            WHERE id = v_exp_id;

            -- Auto-cerrar tareas pendientes del expediente
            UPDATE tareas
            SET estado     = 'CERRADO',
                updated_at = NOW()
            WHERE expediente_id = v_exp_id
              AND estado IN ('PENDIENTE','EN_TRAMITE');

            RAISE NOTICE 'Expediente % mutado AMARILLO/JUZGADO por tipo=%',
                         v_exp_id, NEW.tipo;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ── Trigger AFTER INSERT ─────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_actuaciones_mutacion_automatica ON actuaciones;
CREATE TRIGGER trg_actuaciones_mutacion_automatica
    AFTER INSERT ON actuaciones
    FOR EACH ROW
    EXECUTE FUNCTION fn_actuaciones_mutacion_automatica();

SELECT 'trg_actuaciones_mutacion_automatica OK' AS status;
'@

# Escribir SQL a fichero temporal y pasarlo por stdin a docker exec
$tmpSql = "$env:TEMP\titan_trigger.sql"
Set-Content -Path $tmpSql -Value $triggerSQL -Encoding UTF8

try {
    $result = Get-Content $tmpSql -Raw |
              docker exec -i $PgContainer psql -U $PgUser -d $PgDb 2>&1
    if ($LASTEXITCODE -eq 0) {
        OK "Trigger 'trg_actuaciones_mutacion_automatica' inyectado correctamente."
        Write-Host $result
    } else {
        ERR "Error inyectando trigger:`n$result"
    }
} catch {
    ERR "No se pudo conectar al contenedor '$PgContainer'. Verifica que Docker esté UP."
}
Remove-Item $tmpSql -ErrorAction SilentlyContinue


# ─────────────────────────────────────────────────────────────────────
# PASO 6 — VERIFICAR CONTENEDORES Y ARRANCAR
# ─────────────────────────────────────────────────────────────────────
Log "Paso 6: Verificando contenedores Docker..."

foreach ($container in @($PgContainer, $McpContainer)) {
    $state = docker inspect --format='{{.State.Status}}' $container 2>&1
    if ($state -eq "running") {
        OK "Contenedor '$container' → running"
    } else {
        ERR "Contenedor '$container' no está running (estado: $state)."
        ERR "Ejecuta: docker start $container"
    }
}

# Matar proceso previo en el puerto 8765 si existe
Log "Liberando puerto 8765 si está ocupado..."
$portProc = netstat -ano | Select-String ":8765 " |
            ForEach-Object { ($_ -split "\s+")[-1] } |
            Select-Object -Unique
foreach ($pid in $portProc) {
    if ($pid -match "^\d+$" -and $pid -ne "0") {
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        OK "Proceso $pid en puerto 8765 terminado."
    }
}

# Arrancar titan_pizarra_server.py en background
Log "Arrancando titan_pizarra_server.py en background (puerto 8765)..."
$pythonExe = (Get-Command python -ErrorAction SilentlyContinue)?.Source
if (-not $pythonExe) { $pythonExe = "python3" }

$pizarraScript = "$TitanRoot\titan_pizarra_server.py"
$logFile       = "$TitanRoot\logs\pizarra_server.log"
New-Item -ItemType Directory -Path "$TitanRoot\logs" -Force | Out-Null

$job = Start-Process `
    -FilePath $pythonExe `
    -ArgumentList $pizarraScript `
    -WorkingDirectory $TitanRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $logFile `
    -PassThru

if ($job) {
    OK "titan_pizarra_server.py iniciado (PID $($job.Id)). Log: $logFile"
} else {
    ERR "No se pudo iniciar titan_pizarra_server.py."
}

# Esperar a que el servidor arranque
Log "Esperando arranque del servidor (max 10s)..."
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:8765/" `
                    -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
}

if ($ready) {
    OK "Servidor responde en http://127.0.0.1:8765/"
    # Abrir en navegador predeterminado
    Start-Process "http://127.0.0.1:8765/"
    OK "Navegador abierto en http://127.0.0.1:8765/"
} else {
    ERR "El servidor no respondió en 10s. Revisa $logFile"
}


# ─────────────────────────────────────────────────────────────────────
# RESUMEN FINAL
# ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  INSTALADOR MAESTRO TITÁN — COMPLETADO               " -ForegroundColor Cyan
Write-Host "  Pizarra: http://127.0.0.1:8765/                     " -ForegroundColor Yellow
Write-Host "  FastMCP: http://127.0.0.1:18080/  (docker $McpContainer)" -ForegroundColor Yellow
Write-Host "  Log:     $TitanRoot\logs\pizarra_server.log         " -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
