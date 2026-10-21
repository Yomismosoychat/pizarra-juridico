# INVENTARIO PIZARRA JURÍDICA — AUDITORÍA TÉCNICA
**Generado:** 2026-10-21 · Rama activa: `claude/compact-mode-rbttdt`  
**Auditor:** Claude Code (sesión automática nocturna)

---

## 1. ESTADO DEL REPOSITORIO

| Parámetro | Valor |
|---|---|
| Rama de trabajo | `claude/compact-mode-rbttdt` |
| Rama de producción (GitHub Pages) | `claude/pizarra-juridico-sheets-4jcjoc` |
| URL producción | https://yomismosoychat.github.io/pizarra-juridico/ |
| Último commit (rama activa) | `dc721a4` — ci: redirect 4 writing tests to isolated TEST sheet |
| Commits pendientes de push (sesión anterior) | `2a78e24` (syncSheet), `73f270b` (read intercepts + DOM assertions), `a2932b4` (waitForFunction fix) — **estos commits están en `--all` pero pueden no haberse mergeado a producción** |

---

## 2. ARQUITECTURA DE DATOS — MAPA DE CAMPOS

### 2.1 Google Sheet → Aplicación JS

| Col. Sheet | Nombre Sheet | Variable JS interna | Descripción |
|---|---|---|---|
| A | ID | `c.id` | Identificador estable de fila |
| B | Jurisdicción | `c.cat` | Clave interna (ver tabla CATS abajo) |
| C | Tema | `c.name` | Descripción del caso |
| D | Órgano | `c.court` | Juzgado / Tribunal |
| E | Referencia | `c.ref` | Referencia del procedimiento |
| F | REGAGE | `c.regage` | Número interno REGAGE |
| G | Fecha actuación | `c.trial` | Fecha de juicio / vista oral |
| H | Cuantía | `c.amount` | Importe en euros |
| I | Tipo tarea | `c.nextType` | Clave de próxima acción |
| J | Estado | `c.status` | Estado procesal |
| K | Fecha límite | `c.nextDate` | ← `parseSheetDate(fechaLimite)` |
| L | Días límite | _(calculado)_ | No se almacena en `c` |
| M | ALERTA | _(no importado)_ | Solo visible en Sheet |
| N | Deriva a | _(no importado)_ | Solo visible en Sheet |
| O | Notas | `c.current` | Estado/texto libre actual |
| P | Resultado | `c.resultado` | JSON con resultado del juicio |

### 2.2 Mapas de traducción Sheet ↔ App

**SYNC_STATUS_MAP** (JS interno → Sheet col. J):

| Clave JS | Label Sheet |
|---|---|
| `curso` | En curso |
| `espera` | Esperando respuesta |
| `juicio` | Preparar juicio |
| `actuar` | Actuación pendiente |
| `resuelto` | Resuelto |
| `ganado` | Ganado |
| `perdido` | Perdido |
| `cerrado` | Cerrado |

**SYNC_NEXT_MAP** (JS interno → Sheet col. I):

| Clave JS | Label Sheet |
|---|---|
| `actuar` | Actuar YA |
| `esperar` | Vigilar respuesta |
| `preparar` | Preparar juicio |
| `revisar` | Revisar |

**CATS** (JS interno → Sheet col. B):

| Clave JS | Label Sheet | Color |
|---|---|---|
| `civil` | CIVIL | #6FA8DC |
| `social` | SOCIAL | #6aa84f |
| `penal` | PENAL | #cc4125 |
| `contadmin` | CONTENCIOSO-ADM | #e69138 |
| `familia` | FAMILIA | #d5a6bd |
| `expediente` | EXPEDIENTES | #8e7cc3 |
| `cgpj` | CGPJ | #ea9999 |
| `tc` | TRIBUNAL CONSTITUCIONAL | #ff9900 |
| `tributario` | TRIBUTARIO / INSS | #76a5af |
| `rpatrimonial` | RECL. PATRIMONIALES | #c27ba0 |
| `pendiente` | PENDIENTES INICIAR | #999 |
| `decanato` | DECANATO | #ffb74d |
| `externos` | EXTERNOS | #9fc5e8 |

---

## 3. AUDITORÍA DE CLAVES — FASTMCP vs APP

### 3.1 Claves esperadas por FastMCP (`server.py` local)

Según la modificación aplicada en la sesión anterior a `C:\Titan\local-stack\server.py`:

| Campo FastMCP | Equivalente App JS | Fuente Sheet | Estado |
|---|---|---|---|
| `proxima_actuacion` | `c.nextDate` (cuando `nextType="actuar"`) | Col. K "Fecha límite" | ⚠️ VERIFICAR: puede ser col. G o col. K según implementación |
| `fecha_limite` | `c.nextDate` | Col. K "Fecha límite" | ✅ Coherente |
| `nextType` | `c.nextType` | Col. I "Tipo tarea" | ✅ Coherente |
| `nextDate` | `c.nextDate` | Col. K "Fecha límite" | ✅ Coherente |

### 3.2 ⚠️ AMBIGÜEDAD DETECTADA: `proxima_actuacion`

La app JS usa un único campo `c.nextDate` para dos conceptos distintos:
- Fecha límite de una tarea de tipo "actuar" (col. K)
- Fecha de cualquier próxima actuación

FastMCP tiene `proxima_actuacion` Y `fecha_limite` como campos separados.  
**Riesgo:** si FastMCP mapea `proxima_actuacion` a col. G (Fecha actuación/juicio = `c.trial`) y `fecha_limite` a col. K (`c.nextDate`), la integración es correcta. Si ambos mapean a col. K, hay redundancia.

**Acción recomendada:** Verificar en `server.py` local:
```python
# Debe ser:
"proxima_actuacion": row.get("fecha_actuacion"),  # col G → c.trial
"fecha_limite":      row.get("fecha_limite"),      # col K → c.nextDate
```

### 3.3 Campos eNotum / DEHú

**No hay integración con eNotum o DEHú en el código actual del repositorio.**  
La columna M del Sheet ("ALERTA") no se importa en la app JS.  
**Gap identificado:** Las notificaciones electrónicas de juzgados no están siendo ingestadas ni mostradas en la pizarra.

---

## 4. ALERTAS PROCESALES ACTIVAS — ESTRUCTURA (sin datos en vivo)

La app identifica casos urgentes con `priority=1` (`nextType="actuar"`).  
La función que genera alertas automáticas está en el bloque `checkAutoAlerts()`:

```javascript
// Activación: c.steps contiene "INFORME FORENSE APORTADO"
// Efecto: c.nextType = 'actuar', c.current = '⚠️ REDACTAR ESCRITO...'
```

**Para obtener el listado real de alertas activas**, ejecutar desde Antigravity:
```python
# Consulta PostgreSQL TITÁN:
SELECT id, tema, jurisdiccion, fecha_limite, proxima_actuacion, estado
FROM expedientes
WHERE estado NOT IN ('cerrado', 'ganado', 'perdido')
  AND (fecha_limite IS NOT NULL OR proxima_actuacion IS NOT NULL)
ORDER BY COALESCE(fecha_limite, proxima_actuacion) ASC;
```

O desde Google Sheet (gviz CSV directo):
```
https://docs.google.com/spreadsheets/d/15W3aYgk2m6kqKlbl8TNcB2V38-QmFusaFwrm9gUlzts/gviz/tq?tqx=out:csv&gid=953772179
```

---

## 5. ESTADO DE CI/CD

### 5.1 Jobs de GitHub Actions (`.github/workflows/test-sheet-load.yml`)

| Job | Descripción | Estado último run conocido |
|---|---|---|
| `test-civil-count` | Lectura producción, count CIVIL ≥ 1 | ✅ Stable (solo lectura) |
| `test-form-submit` | Crea caso → verifica CSV → borra | ⚠️ Requiere confirmar run post-commit `73f270b` |
| `test-externos-group` | Crea caso EXTERNOS → verifica subgrupo → borra | ⚠️ Fix `waitForFunction` aplicado en `a2932b4` — pendiente confirmar |
| `test-trash-cerrar` | Crea → cierra → verifica `detail-${cerrId}` → verifica `.btn-trash[onclick*="${borrarId}"]` → borra | ⚠️ Fix específico aplicado en `73f270b` |
| `test-activar-pendiente` | Crea PENDIENTE → activa → verifica `detail-${pendId}` en CIVIL → borra | ⚠️ Fix específico aplicado en `73f270b` |

### 5.2 Sheets usadas en CI

| Sheet | ID | GID | Uso |
|---|---|---|---|
| PRODUCCIÓN | `15W3aYgk2m6kqKlbl8TNcB2V38-QmFusaFwrm9gUlzts` | `953772179` | Solo lectura (`test-civil-count`) |
| TEST | `1666QZMGfHcRontlMBukwa8jq6fSNotmczob_Z4sfc9g` | `953772179` | Escritura aislada (4 jobs de escritura) |

**⛔ REGLA CRÍTICA: NUNCA escribir desde CI a PROD_SHEET_ID.**

---

## 6. FUNCIONES PENDIENTES DE IMPLEMENTAR

| Función | Estado | Impacto |
|---|---|---|
| `getAllRows()` | ❌ NO EXISTE en el código | `syncSheet()` lanzará `ReferenceError` si se llama |
| `rowToSheetCols(row)` | ❌ NO EXISTE en el código | Ídem |
| Botón UI "📤 Sync Sheet" | ❌ NO EXISTE en el HTML | `syncSheet()` definida pero sin punto de entrada |

**Nota:** El commit `2a78e24` añadió `syncSheet()` y `APPS_SCRIPT_URL` pero está en la rama `claude/pizarra-juridico-sheets-4jcjoc`, no en `claude/compact-mode-rbttdt`. Verificar estado exacto antes de implementar `getAllRows()`.

---

## 7. ENDPOINTS Y CREDENCIALES (referencia rápida)

| Recurso | URL / Valor |
|---|---|
| WEBAPP_URL (escritura unidireccional) | `https://script.google.com/macros/s/AKfycbyxEpXi44bsdVXy0ms25x8JzQGOwFcKNEWZnCUDos4lJRs0_tmgBk_eQcdofRsFqei_/exec` |
| WEBAPP_TOKEN | `vKPe__KvDIkkJ56R7bOQUaM7DuquoFcTS0zF9UC9Fjc` |
| APPS_SCRIPT_URL (sync bidireccional) | `https://script.google.com/macros/s/AKfycbw5VUPfvxVDY5wd2gWnO73_VV3EP080HNUQCxTZfrI8FGSjkrykIbrAUXtvnPHk8T6n/exec` |
| TITAN FastMCP | `http://localhost:18080` (local Windows) |
| TITAN PostgreSQL | `localhost:5432` (Docker titan-fastmcp) |

---

## 8. CHECKLIST PARA MAÑANA (ANTIGRAVITY)

- [ ] Verificar `proxima_actuacion` en `server.py`: ¿mapea a col G o col K?
- [ ] Ejecutar query de alertas activas en PostgreSQL TITÁN (ver §4)
- [ ] Confirmar que los 5 jobs CI están verdes en la rama `claude/compact-mode-rbttdt`
- [ ] Implementar `getAllRows()` y `rowToSheetCols()` antes de activar `syncSheet()`
- [ ] Añadir botón "📤 Sync Sheet" al topbar de `index.html`
- [ ] Verificar que columna M ("ALERTA") del Sheet no contiene alertas eNotum/DEHú sin procesar

---

*Archivo generado automáticamente por Claude Code. Verificar datos en vivo antes de tomar decisiones procesales.*
