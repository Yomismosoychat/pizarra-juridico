# AGENTS.md — TITÁN Pizarra Jurídica
## Directivas para todos los agentes con acceso a este repositorio o al ecosistema TITÁN

---

## DRIVE WRITE BOUNDARY — DIRECTIVA CERO (v1.0 · 2026-10-22)

Todo agente (Claude, Antigravity, n8n, Evolution Watcher, JARVIS, FastMCP, futuro) que
tenga credenciales de Google Drive **debe** cumplir esta directiva antes de cualquier
operación de escritura:

### 1. Raíces

| ID | Label | Modo IA |
|---|---|---|
| `1QUhASnACfWqZfcHjsaeGkZfLlUUnj7A5` | TITAN | READ_ONLY |
| `1DsG9aex_8fI_xf2ESw0W1CQHl4ulFg1s` | VOLCADOS SINCRO | READ_WRITE |

### 2. Verificación obligatoria

Antes de `CREATE / UPLOAD / MOVE / RENAME / DELETE / COPY_INTO / CREATE_FOLDER`:

1. Resolver recursivamente la cadena de padres del `target_parent_id` via Drive API.
2. Si la cadena alcanza `1QUhASnACfWqZfcHjsaeGkZfLlUUnj7A5` → **DENY** con `ERR-DRIVE-001`.
3. Si la cadena NO alcanza `1DsG9aex_8fI_xf2ESw0W1CQHl4ulFg1s` → **DENY**.
4. Si no puede resolverse la cadena → **DENY**.
5. Registrar intento bloqueado en `C:\Titan\logs\drive_write_guard_audit.jsonl`.

### 3. Implementación de referencia

```python
from drive_write_guard import DriveWriteGuard
guard = DriveWriteGuard(drive_service)
guard.assert_drive_write_allowed(target_parent_id, operation, agent="mi-agente")
```

### 4. Prohibición de duplicados por nombre de juzgado

**NUNCA** crear carpetas a partir del nombre del órgano judicial.
Asociar siempre por `case_id → drive_folder_id`.

---

## HOJAS GOOGLE SHEET — REGLA CI

- **NUNCA** escribir desde CI a `PROD_SHEET_ID = 15W3aYgk2m6kqKlbl8TNcB2V38-QmFusaFwrm9gUlzts`
- Escritura CI solo a `TEST_SHEET_ID = 1666QZMGfHcRontlMBukwa8jq6fSNotmczob_Z4sfc9g`

---

## CADENAS DE PADRES VERIFICADAS (2026-10-22)

```
Zona protegida (TITAN):
  CIVIL (1wzrSyaOy2rv)
  → 1. Justicia -España (1JE5jstNXjOB)
  → 1.PROYECTOS-DENUNCIAS (19pIjXPqdqrj)
  → TITAN ← PROTECTED_USER_ROOT_ID

Zona IA (VOLCADOS SINCRO):
  VOLCADOS SINCRO (1DsG9aex_8fI)
  → My Drive root (1fxsHnqj0BTc)
```
