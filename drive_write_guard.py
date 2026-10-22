#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
drive_write_guard.py — TITÁN Drive Write Boundary  v1.0  2026-10-22
Ubicación canónica: C:\Titan\local-stack\drive_write_guard.py

Salvaguarda estructural permanente que impide que cualquier agente
o automatización TITÁN escriba en la zona protegida del usuario.

RAÍCES CANÓNICAS
    PROTECTED_USER_ROOT_ID = 1QUhASnACfWqZfcHjsaeGkZfLlUUnj7A5  → TITAN (usuario)
    AI_WRITE_ROOT_ID       = 1DsG9aex_8fI_xf2ESw0W1CQHl4ulFg1s  → VOLCADOS SINCRO (IA)

REGLA ABSOLUTA
    Ningún agente puede CREATE/UPLOAD/MOVE/RENAME/DELETE/COPY_INTO/CREATE_FOLDER
    en cualquier ruta cuyo árbol de padres alcance PROTECTED_USER_ROOT_ID.
    Solo se permite escribir si el árbol alcanza AI_WRITE_ROOT_ID.
    Si no puede verificarse: DENY.

ERROR ESTÁNDAR: ERR-DRIVE-001  BLOCKED_PROTECTED_DRIVE_ZONE
"""

from __future__ import annotations

import datetime
import json
import logging
import os
import pathlib
from typing import Any, Optional

# ── Raíces canónicas ────────────────────────────────────────────────────────
PROTECTED_USER_ROOT_ID = "1QUhASnACfWqZfcHjsaeGkZfLlUUnj7A5"
AI_WRITE_ROOT_ID       = "1DsG9aex_8fI_xf2ESw0W1CQHl4ulFg1s"

# ── Operaciones destructivas/creativas bloqueadas en zona protegida ─────────
PROTECTED_OPERATIONS = frozenset({
    "CREATE", "UPLOAD", "MOVE", "RENAME",
    "DELETE", "COPY_INTO", "CREATE_FOLDER",
})

# ── Ruta del log de auditoría ────────────────────────────────────────────────
_DEFAULT_AUDIT_PATH = pathlib.Path(r"C:\Titan\logs\drive_write_guard_audit.jsonl")

logger = logging.getLogger("drive_write_guard")


class DriveWriteGuardError(PermissionError):
    """ERR-DRIVE-001 — operación bloqueada en zona protegida."""
    code = "ERR-DRIVE-001"
    reason = "BLOCKED_PROTECTED_DRIVE_ZONE"


class DriveWriteGuard:
    """
    Componente central de protección de Drive.

    Uso:
        guard = DriveWriteGuard(drive_service)
        guard.assert_drive_write_allowed(parent_id, "CREATE", agent="n8n")

    Lanza DriveWriteGuardError si la operación está bloqueada.
    """

    def __init__(
        self,
        drive_service: Any,
        audit_path: Optional[pathlib.Path] = None,
        max_depth: int = 20,
    ):
        self.drive = drive_service
        self.audit_path = audit_path or _DEFAULT_AUDIT_PATH
        self.max_depth = max_depth
        self._cache: dict[str, list[str]] = {}

    # ── API pública ─────────────────────────────────────────────────────────

    def assert_drive_write_allowed(
        self,
        target_parent_id: str,
        operation: str,
        agent: str = "TITAN",
    ) -> None:
        """
        Verifica que la operación sea segura.

        Lanza DriveWriteGuardError con ERR-DRIVE-001 si no lo es.
        No hace nada si la operación no es destructiva/creativa.
        """
        if operation not in PROTECTED_OPERATIONS:
            return  # lectura siempre permitida

        chain = self._resolve_parent_chain(target_parent_id)
        resolved_root = chain[-1] if chain else target_parent_id

        log: dict[str, Any] = {
            "timestamp":        datetime.datetime.utcnow().isoformat() + "Z",
            "agent":            agent,
            "operation":        operation,
            "target_parent_id": target_parent_id,
            "resolved_root_id": resolved_root,
            "chain":            chain,
        }

        # BLOQUEO 1: alcanza la zona protegida del usuario
        if PROTECTED_USER_ROOT_ID in chain:
            log["reason"] = "BLOCKED_PROTECTED_DRIVE_ZONE"
            self._write_audit(log)
            logger.warning("BLOCKED %s on %s — chain reaches PROTECTED_USER_ROOT", operation, target_parent_id)
            raise DriveWriteGuardError(
                f"ERR-DRIVE-001 BLOCKED_PROTECTED_DRIVE_ZONE\n"
                f"Operation '{operation}' by agent '{agent}' on parent '{target_parent_id}' "
                f"reaches protected root '{PROTECTED_USER_ROOT_ID}'.\n"
                f"Parent chain: {' → '.join(chain)}"
            )

        # BLOQUEO 2: no alcanza la zona de escritura IA
        if AI_WRITE_ROOT_ID not in chain:
            log["reason"] = "NOT_IN_AI_WRITE_ZONE"
            self._write_audit(log)
            logger.warning("DENIED %s on %s — chain does not reach AI_WRITE_ROOT", operation, target_parent_id)
            raise DriveWriteGuardError(
                f"ERR-DRIVE-001 BLOCKED_PROTECTED_DRIVE_ZONE\n"
                f"Operation '{operation}' by agent '{agent}' on parent '{target_parent_id}' "
                f"does not reach AI_WRITE_ROOT_ID '{AI_WRITE_ROOT_ID}'. DENY.\n"
                f"Parent chain: {' → '.join(chain)}"
            )

        # PERMITIDO
        log["reason"] = "ALLOWED_AI_WRITE_ZONE"
        self._write_audit(log)
        logger.info("ALLOWED %s on %s", operation, target_parent_id)

    # ── Resolución recursiva de padres ──────────────────────────────────────

    def _resolve_parent_chain(self, folder_id: str) -> list[str]:
        """
        Recorre recursivamente los padres de folder_id hasta la raíz.
        Devuelve lista [folder_id, parent1, parent2, …, root].
        Identifica raíz anticipadamente si alcanza una de las dos conocidas.
        """
        chain: list[str] = []
        current = folder_id
        visited: set[str] = set()

        for _ in range(self.max_depth):
            if current in visited:
                logger.warning("Cycle detected in parent chain at %s", current)
                break
            visited.add(current)
            chain.append(current)

            # Early exit en raíces conocidas
            if current in (PROTECTED_USER_ROOT_ID, AI_WRITE_ROOT_ID):
                break

            parents = self._get_parents(current)
            if not parents:
                break  # raíz de My Drive

            current = parents[0]

        return chain

    def _get_parents(self, file_id: str) -> list[str]:
        """Obtiene los padres de un fichero/carpeta via Drive API."""
        if file_id in self._cache:
            return self._cache[file_id]
        try:
            meta = (
                self.drive.files()
                .get(fileId=file_id, fields="parents")
                .execute()
            )
            parents = meta.get("parents", [])
        except Exception as exc:
            logger.error("Cannot resolve parents of %s: %s", file_id, exc)
            parents = []
        self._cache[file_id] = parents
        return parents

    # ── Auditoría ───────────────────────────────────────────────────────────

    def _write_audit(self, entry: dict[str, Any]) -> None:
        """Append-only JSON Lines en audit_path."""
        try:
            self.audit_path.parent.mkdir(parents=True, exist_ok=True)
            with self.audit_path.open("a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except Exception as exc:
            logger.error("Audit write failed: %s", exc)


# ── Helper de integración rápida (sin instanciar clase) ─────────────────────

def assert_drive_write_allowed(
    target_parent_id: str,
    operation: str,
    drive_service: Any,
    agent: str = "TITAN",
    audit_path: Optional[pathlib.Path] = None,
) -> None:
    """Shortcut funcional para verificación puntual."""
    DriveWriteGuard(drive_service, audit_path=audit_path).assert_drive_write_allowed(
        target_parent_id, operation, agent
    )


# ── MATRIZ TITÁN — constantes exportables ───────────────────────────────────
DRIVE_MATRIX = {
    "DRIVE_USER_ZONE": {
        "id":      PROTECTED_USER_ROOT_ID,
        "mode":    "READ_ONLY_FOR_AI",
        "owner":   "ANTONIO",
        "label":   "TITAN",
    },
    "DRIVE_AI_ZONE": {
        "id":      AI_WRITE_ROOT_ID,
        "mode":    "READ_WRITE",
        "purpose": "VOLCADOS_SINCRO",
        "label":   "VOLCADOS SINCRO",
    },
}
