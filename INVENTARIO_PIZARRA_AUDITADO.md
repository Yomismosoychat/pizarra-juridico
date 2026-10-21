# INVENTARIO PIZARRA JURÍDICA — AUDITORÍA TÉCNICA
**Generado:** 2026-10-21 · Actualizado: 2026-10-21 (post-Antigravity)  
**Rama activa:** `claude/compact-mode-rbttdt`  
**Estado consolidación:** ✅ 53 expedientes sincronizados · 19 actuaciones insertadas

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

### 3.1 Mapeo técnico certificado por Antigravity (`cargar_pizarra.py`)

| Campo FastMCP (`actualizar_pizarra`) | Equivalente App JS | Col. Sheet | Tipo | Estado |
|---|---|---|---|---|
| `proxima_actuacion` | _(texto descriptivo)_ | — | `str` — descripción textual de la próxima acción | ✅ CERTIFICADO |
| `fecha_limite` | `c.nextDate` | K "Fecha límite" | `str` YYYY-MM-DD — vencimiento procesal fatal | ✅ CERTIFICADO |
| `c_trial` | `c.trial` | G "Fecha actuación" | `str` YYYY-MM-DD — fecha de juicio/vista | ✅ CERTIFICADO |
| `c_nextDate` | `c.nextDate` | K "Fecha límite" | `str` YYYY-MM-DD — idéntico a `fecha_limite` | ✅ CERTIFICADO |
| `alerta` | _(no en App JS todavía)_ | M "ALERTA" | `str` — notificaciones eNotum/DEHú | ✅ CERTIFICADO |
| `drive_url` | — | — | `None` para fuentes no Drive (Gmail, eNotum, DEHú, OAC, local) | ✅ CERTIFICADO |

**Resolución de ambigüedad §3.2 (anterior):** `proxima_actuacion` es un **texto libre descriptivo** (ej: "Examinar diligencia 315749249..."), NO una fecha. La fecha va en `fecha_limite` / `c_nextDate`. Los dos campos son funcionalmente distintos.

### 3.2 Herramientas MCP utilizadas por `cargar_pizarra.py`

| Herramienta | Propósito |
|---|---|
| `actualizar_pizarra` | Upsert de expediente completo con todos sus campos |
| `insertar_actuacion` | Inserción de actuación/notificación individual |

### 3.3 Integración eNotum / DEHú — CONFIRMADA ✅

Las alertas de sedes electrónicas **SÍ están integradas** en TITÁN vía campo `alerta` (Col. M) y actuaciones de tipo `ALERTA_DEHU` / `ALERTA_ENOTUM` en `cargar_pizarra.py`.

Ejemplo confirmado (`civ6-quiero`):
- DEHú id 155 → `ALERTA_DEHU` → 2026-09-24 — SCiv Pl. 06 TGN 993/2026-M56
- eNotum id 156 → `ALERTA_ENOTUM` → 2026-09-24 — Avís notificació SECR. RELACIONS AMB L'ADM. JUSTÍCIA

**Gap parcial:** El campo `alerta` de la App JS (Pizarra web) no se renderiza en las tarjetas todavía — solo existe en PostgreSQL/FastMCP.

---

## 4. ALERTAS PROCESALES ACTIVAS — ORDENADAS POR RIESGO Y FECHA

Datos certificados por Antigravity · 2026-10-21 · Total: 53 expedientes, 19 actuaciones

### 4.1 PRIORIDAD ROJO (acción inmediata)

| Expediente | Próxima actuación | Fecha límite | Alerta |
|---|---|---|---|
| `rp-reus` | Verificar actuación sobre fecha límite ya vencida | **2026-10-20** ⛔ VENCIDA | Presentación pendiente de verificar |
| `civ8-caxa` | Examinar diligencia 315749249 | **2026-10-20** | Acceso no acreditado |
| `civ3-port` | Examinar decreto admisión notif. 317916366 | **2026-10-22** | Contenido íntegro pendiente |
| `soc2-pension` | Examinar providencia 318932486 + diligencia 318991338 | **2026-10-26** | Dos notificaciones distintas |
| `cont1-torre` | Examinar diligencia + traslado expediente adm. | **2026-10-26** | Contenido pendiente |
| `cont3-bcn-189-2014` | Contrastar requerimiento judicial (posible plazo 3 días) | _no determinada_ | Plazo declarado en correo, no acreditado |
| `pen-tsjc` | Preparar recurso de súplica ante TSJC | — | — |
| `pen-imput` | Seguimiento Juzgado Guardia, FGE y Fiscalía Superior | — | — |

### 4.2 PRIORIDAD NARANJA

| Expediente | Próxima actuación | Fecha límite | Alerta |
|---|---|---|---|
| `rp-imput` | Seguimiento reclamación patrimonial | **2026-10-28** | — |
| `zar-9550871-6` | Comprobar remisión postal del poder | _no determinada_ | Posible incidencia documental |

### 4.3 PRIORIDAD MEDIA con fecha

| Expediente | Próxima actuación | Fecha límite | Alerta |
|---|---|---|---|
| `civ6-quiero` | Esperar resolución | **2026-11-30** | DEHú id 155 + eNotum id 156 |

### 4.4 Juicios señalados (c_trial)

| Expediente | Fecha juicio |
|---|---|
| `soc3-brecha` | 2028-05-30 |
| `soc2-paro` | 2027-07-07 |

### 4.5 Expedientes PENDIENTES DE INICIAR

| Expediente | Próxima actuación |
|---|---|
| `pend-caida` | Preparar y registrar denuncia por caída |
| `pend-medico` | Preparar y registrar denuncia médica |
| `pend-inss` | Preparar denuncia contra INSS |

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

### Completado en sesión nocturna ✅
- [x] Mapeo técnico Coword certificado (`proxima_actuacion` = texto, `fecha_limite` = Col K, `c_trial` = Col G)
- [x] 53 expedientes sincronizados a PostgreSQL TITÁN
- [x] 19 actuaciones insertadas (incl. 2 alertas DEHú/eNotum de `civ6-quiero`)
- [x] `cargar_pizarra.py` validado y ejecutado

### Pendiente — App JS (Pizarra web)
- [ ] Implementar `getAllRows()` y `rowToSheetCols()` para activar `syncSheet()`
- [ ] Añadir botón "📤 Sync Sheet" al topbar de `index.html`
- [ ] Renderizar campo `alerta` (Col M) en las tarjetas de la Pizarra web

### Pendiente — CI/CD
- [ ] Confirmar que los 5 jobs CI están verdes en la rama `claude/compact-mode-rbttdt`
- [ ] Mergear commits `2a78e24`, `73f270b`, `a2932b4` de `claude/pizarra-juridico-sheets-4jcjoc` a producción

### Acción procesal urgente
- [ ] **`rp-reus`** — fecha límite 2026-10-20 **YA VENCIDA** → verificar si presentación fue realizada
- [ ] **`civ8-caxa`** — examinar diligencia 315749249 (límite 2026-10-20)
- [ ] **`civ3-port`** — examinar notif. 317916366 (límite 2026-10-22)
- [ ] **`soc2-pension`** + **`cont1-torre`** — examinar notificaciones (límite 2026-10-26)

---

*Archivo generado automáticamente por Claude Code. Verificar datos en vivo antes de tomar decisiones procesales.*
