# CLAUDE.md — TITÁN Pizarra Jurídica
## Reglas permanentes para agentes Claude en este repositorio

---

## DRIVE WRITE BOUNDARY — REGLA ABSOLUTA (v1.0 · 2026-10-22)

### Raíces canónicas

```
PROTECTED_USER_ROOT_ID = 1QUhASnACfWqZfcHjsaeGkZfLlUUnj7A5   # TITAN  (solo lectura para IA)
AI_WRITE_ROOT_ID       = 1DsG9aex_8fI_xf2ESw0W1CQHl4ulFg1s   # VOLCADOS SINCRO  (lectura/escritura)
```

### Regla

Ningún agente puede ejecutar `CREATE / UPLOAD / MOVE / RENAME / DELETE / COPY_INTO / CREATE_FOLDER`
en ninguna ruta cuyo árbol de padres alcance `PROTECTED_USER_ROOT_ID`.

Escritura permitida **únicamente** si la cadena de padres alcanza `AI_WRITE_ROOT_ID`.
Si no puede verificarse la cadena: **DENY**.

No usar coincidencia por nombre de carpeta — siempre resolver por Drive ID.

### Error estándar

```
ERR-DRIVE-001  BLOCKED_PROTECTED_DRIVE_ZONE
```

### Módulo de implementación

`drive_write_guard.py` → función `assert_drive_write_allowed(target_parent_id, operation, drive_service)`

Copia canónica local: `C:\Titan\local-stack\drive_write_guard.py`

---

## PREVENCIÓN DE DUPLICADOS JUDICIALES

La asociación expediente ↔ Drive se realiza mediante `case_id → drive_folder_id`.
**Prohibido** crear carpetas a partir del nombre del órgano judicial.

Caso de regresión:
- Carpeta canónica: `Civil 8 TI Tarragona - Anna Matias 1229-2026-M53` → `1nhXWj4ktM4tNG517U3vq6RAjupu3CipH`
- Carpeta duplicada errónea (`Juzgado PRIMERA INSTANCIA N.º 8 DE TARRAGONA` → `1G1s7c_cfFGTHi0VgF96tU7-xq61HU59c`) ya no existe en Drive.

---

## MATRIZ TITÁN

```yaml
DRIVE_USER_ZONE:
  id:    1QUhASnACfWqZfcHjsaeGkZfLlUUnj7A5
  mode:  READ_ONLY_FOR_AI
  owner: ANTONIO
  label: TITAN

DRIVE_AI_ZONE:
  id:      1DsG9aex_8fI_xf2ESw0W1CQHl4ulFg1s
  mode:    READ_WRITE
  purpose: VOLCADOS_SINCRO
  label:   VOLCADOS SINCRO
```

---

## RAMA DE TRABAJO

Rama activa: `claude/compact-mode-rbttdt`
Rama de producción (GitHub Pages): `claude/pizarra-juridico-sheets-4jcjoc`

## REGLAS DE SHEET

- **PRODUCCIÓN:** `15W3aYgk2m6kqKlbl8TNcB2V38-QmFusaFwrm9gUlzts` — **NUNCA escribir desde CI**
- **TEST:** `1666QZMGfHcRontlMBukwa8jq6fSNotmczob_Z4sfc9g` — escritura aislada en CI
