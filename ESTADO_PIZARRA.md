# ESTADO PIZARRA JURÍDICA — Septiembre 2026

## URL de producción
**https://yomismosoychat.github.io/pizarra-juridico/**

Rama de GitHub Pages: `claude/pizarra-juridico-sheets-4jcjoc`

---

## Apps Script Web App

**URL:** `https://script.google.com/macros/s/AKfycbyxEpXi44bsdVXy0ms25x8JzQGOwFcKNEWZnCUDos4lJRs0_tmgBk_eQcdofRsFqei_/exec`

**Acciones soportadas (POST JSON):**

| `action` | Efecto | Campos obligatorios |
|---|---|---|
| _(inserción)_ | Crea nueva fila antes de TOTAL | `jurisdiccion`, `tema`, `fechaActuacion` |
| `delete` | Elimina fila por ID (col. A) | `id` |
| `update` | Actualiza un campo de la fila | `id`, `campo`, `valor` |

**Campos de `update`:**

| `campo` | Columna | Notas |
|---|---|---|
| `estado` | J | Valor literal en Sheet. `"cerrado"` → caso cerrado. |
| `jurisdiccion` | B | Label Sheet (CIVIL, SOCIAL, PENAL…). Reclasifica el caso. |

**Despliegue manual (requerido para cambios en Code.gs):**
1. Abrir Apps Script: https://script.google.com/home
2. Pegar contenido de `/tmp/.../scratchpad/Code.gs`
3. Desplegar → Gestionar implementaciones → Editar versión existente → Nueva versión → Guardar

---

## Google Sheet

- **ID:** `15W3aYgk2m6kqKlbl8TNcB2V38-QmFusaFwrm9gUlzts`
- **GID (PANEL):** `953772179`
- **Columnas:** A=ID, B=Jurisdicción, C=Tema, D=Órgano, E=Referencia, F=REGAGE, G=Fecha actuación / TOTAL, H=Cuantía, I=Tipo tarea, J=Estado, K=Fecha límite, L=Días límite, M=ALERTA, N=Deriva a, O=Notas

---

## Funcionalidades implementadas

### PANEL (vista por defecto)
- Carga desde Sheet vía gviz CSV (no requiere autenticación, solo "ver con enlace")
- Guardado local en localStorage + sync con Sheet vía Web App

### Vista Grupos
- Grupos normales (CIVIL, SOCIAL, PENAL, CONTENCIOSO-ADM, etc.) excluyen casos cerrados
- Separador doble dashed
- **1º PENDIENTES DE INICIAR** — casos con `cat=pendiente` no cerrados
- **2º CASOS CERRADOS** — todos los casos con `status=cerrado`, independientemente de su jurisdicción original

### Tarjeta (renderCard)
| Botón | Acción |
|---|---|
| ✅ HECHO | Registra paso/actuación |
| ▲/▼ Detalle | Expande detalle |
| ▶️ Activar | Solo visible en PENDIENTES. Abre modal para reclasificar jurisdicción. |
| ⛔ Cerrar caso | No visible si ya cerrado. Llama `action:update campo:estado valor:cerrado`. |
| 🗑️ | Confirma y llama `action:delete`. Recarga desde Sheet. |

### Modal Activar pendiente (`#activar-overlay`)
- Selector dinámico de jurisdicción (excluye `pendiente` y `externos`)
- Llama `action:update campo:jurisdiccion valor:<LABEL>`
- Actualiza local: `c.cat`, `c.status = "curso"`, luego `render()` + `scheduleSave()`

---

## CI/CD (GitHub Actions)

Archivo: `.github/workflows/test-sheet-load.yml`

| Job | Qué prueba |
|---|---|
| `test-civil-count` | Carga la app, cuenta casos CIVIL, verifica count ≥ 1 |
| `test-form-submit` | Crea caso vía modal Nuevo caso, verifica en CSV, borra |
| `test-externos-group` | Crea caso EXTERNOS, verifica subcarpeta, cuantía, borra |
| `test-trash-cerrar` | Crea caso, llama `action:update estado=cerrado`, verifica CSV, verifica grupo CASOS CERRADOS, verifica botón .btn-trash, borra |
| `test-activar-pendiente` | Crea caso PENDIENTES, llama `action:update jurisdiccion=CIVIL`, verifica CSV, verifica `#activar-overlay` en DOM, borra |

---

## Historial de cambios relevantes

| Fecha | Cambio |
|---|---|
| Sep 2026 | Fix CI test-form-submit: `selectOption` usa `{ index: 1 }` (dropdown dinámico) |
| Sep 2026 | Grupo EXTERNOS añadido; Web App Code.gs con acción `delete` y lógica TOTAL |
| Sep 2026 | TAREA 1: botón 🗑️ borrarCaso |
| Sep 2026 | TAREA 2: botón ⛔ cerrarCaso; `SYNC_STATUS_MAP` añade `cerrado→Cerrado` |
| Sep 2026 | TAREA 3: renderGrouped reescrito con doble separador + PENDIENTES + CASOS CERRADOS |
| Sep 2026 | TAREA 4: botón ▶️ activarPendiente + modal #activar-overlay |
| Sep 2026 | TAREA 5: tests CI test-trash-cerrar + test-activar-pendiente |
