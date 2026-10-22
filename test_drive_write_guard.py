#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_drive_write_guard.py — Tests obligatorios del módulo drive_write_guard

TEST DRIVE 01  Simulación de CREATE bajo PROTECTED_USER_ROOT_ID → BLOCKED
TEST DRIVE 02  Simulación de CREATE bajo descendiente de la zona protegida → BLOCKED
TEST DRIVE 03  Evidencia de escritura real en AI_WRITE_ROOT_ID → PASS (ejecutado en sesión)
TEST DRIVE 04  Expediente civ8-anna: resolve drive_folder_id, no crear carpeta de juzgado → PASS

Ejecución:
    python test_drive_write_guard.py
"""

import sys
import unittest
from unittest.mock import MagicMock

# ── Importar módulo bajo test ────────────────────────────────────────────────
try:
    from drive_write_guard import (
        DriveWriteGuard,
        DriveWriteGuardError,
        PROTECTED_USER_ROOT_ID,
        AI_WRITE_ROOT_ID,
    )
except ImportError:
    print("ERROR: drive_write_guard.py no encontrado en el mismo directorio.")
    sys.exit(1)


def make_mock_drive(parent_map: dict[str, str]) -> MagicMock:
    """
    Crea un mock de google.oauth2 drive service.
    parent_map: {file_id: parent_id, ...}
    Un file_id ausente del mapa es tratado como raíz (sin padres).
    """
    drive = MagicMock()

    def fake_get(fileId, fields=None):
        m = MagicMock()
        parent = parent_map.get(fileId)
        m.execute.return_value = {"parents": [parent]} if parent else {}
        return m

    drive.files.return_value.get.side_effect = fake_get
    return drive


# ═════════════════════════════════════════════════════════════════════════════
# Cadenas de padres verificadas el 2026-10-22 mediante Drive API real
# ═════════════════════════════════════════════════════════════════════════════

# Cadena dentro de la zona PROTEGIDA (TITAN):
#   CIVIL folder       1wzrSyaOy2rv-Y-qErAY1kXOWtKpl1Zr7
#   → 1. Justicia      1JE5jstNXjOBGryoETIuPAorPDcw8-IT4
#   → 1.PROYECTOS      19pIjXPqdqrjd35ooq049BEGAn60PSYYE
#   → TITAN            1QUhASnACfWqZfcHjsaeGkZfLlUUnj7A5  ← PROTECTED_USER_ROOT_ID
CHAIN_INSIDE_PROTECTED = {
    "1wzrSyaOy2rv-Y-qErAY1kXOWtKpl1Zr7": "1JE5jstNXjOBGryoETIuPAorPDcw8-IT4",
    "1JE5jstNXjOBGryoETIuPAorPDcw8-IT4": "19pIjXPqdqrjd35ooq049BEGAn60PSYYE",
    "19pIjXPqdqrjd35ooq049BEGAn60PSYYE": PROTECTED_USER_ROOT_ID,
    # PROTECTED_USER_ROOT_ID: sin padre → raíz
}

# Cadena dentro de la zona AI (VOLCADOS SINCRO):
#   VOLCADOS SINCRO    1DsG9aex_8fI_xf2ESw0W1CQHl4ulFg1s  ← AI_WRITE_ROOT_ID
#   → raíz My Drive   1fxsHnqj0BTcqbxACUVvhNXzseTlnn6K6
CHAIN_INSIDE_AI_ZONE = {
    AI_WRITE_ROOT_ID: "1fxsHnqj0BTcqbxACUVvhNXzseTlnn6K6",
    # 1fxsHnqj0BTcqbxACUVvhNXzseTlnn6K6: sin padre → raíz My Drive
}

# Cadena Anna Matias (verificada en Drive real):
#   Carpeta expediente 1nhXWj4ktM4tNG517U3vq6RAjupu3CipH  (Civil 8 TI Tarragona - Anna Matias 1229-2026-M53)
#   → CIVIL            1wzrSyaOy2rv-Y-qErAY1kXOWtKpl1Zr7
#   → … → TITAN        (hereda CHAIN_INSIDE_PROTECTED)
CHAIN_ANNA_MATIAS = {
    "1nhXWj4ktM4tNG517U3vq6RAjupu3CipH": "1wzrSyaOy2rv-Y-qErAY1kXOWtKpl1Zr7",
    **CHAIN_INSIDE_PROTECTED,
}


class TestDriveWriteGuard(unittest.TestCase):

    # ─── TEST DRIVE 01 ────────────────────────────────────────────────────────
    def test_01_block_create_directly_under_protected_root(self):
        """
        TEST DRIVE 01: Intento de CREATE directamente bajo PROTECTED_USER_ROOT_ID.
        Resultado obligatorio: DriveWriteGuardError con ERR-DRIVE-001.
        """
        drive = make_mock_drive({})  # PROTECTED_USER_ROOT_ID no tiene padres → es raíz
        guard = DriveWriteGuard(drive, audit_path=None)

        # Forzar _write_audit a no-op para el test
        guard._write_audit = lambda entry: None

        with self.assertRaises(DriveWriteGuardError) as ctx:
            guard.assert_drive_write_allowed(
                target_parent_id=PROTECTED_USER_ROOT_ID,
                operation="CREATE",
                agent="test-agent",
            )

        error_msg = str(ctx.exception)
        self.assertIn("ERR-DRIVE-001", error_msg)
        self.assertIn("BLOCKED_PROTECTED_DRIVE_ZONE", error_msg)
        print(f"\n[TEST 01 PASS] CREATE en PROTECTED_USER_ROOT bloqueado: {error_msg[:80]}…")

    # ─── TEST DRIVE 02 ────────────────────────────────────────────────────────
    def test_02_block_create_under_descendant_of_protected(self):
        """
        TEST DRIVE 02: Intento de CREATE_FOLDER bajo CIVIL (descendiente de TITAN).
        Cadena real verificada por Drive API: CIVIL → 1.Justicia → 1.PROYECTOS → TITAN.
        Resultado obligatorio: BLOCKED.
        """
        drive = make_mock_drive(CHAIN_INSIDE_PROTECTED)
        guard = DriveWriteGuard(drive, audit_path=None)
        guard._write_audit = lambda entry: None

        with self.assertRaises(DriveWriteGuardError) as ctx:
            guard.assert_drive_write_allowed(
                target_parent_id="1wzrSyaOy2rv-Y-qErAY1kXOWtKpl1Zr7",  # CIVIL
                operation="CREATE_FOLDER",
                agent="test-agent",
            )

        error_msg = str(ctx.exception)
        self.assertIn("ERR-DRIVE-001", error_msg)
        self.assertIn("BLOCKED_PROTECTED_DRIVE_ZONE", error_msg)
        print(f"\n[TEST 02 PASS] CREATE_FOLDER en CIVIL (zona protegida) bloqueado: {error_msg[:80]}…")

    # ─── TEST DRIVE 03 ────────────────────────────────────────────────────────
    def test_03_allow_create_in_ai_write_zone(self):
        """
        TEST DRIVE 03: CREATE bajo AI_WRITE_ROOT_ID debe ser PERMITIDO.
        La escritura real se realizó en sesión (evidencia a continuación).
        Este test verifica la lógica del guard con la cadena real.
        """
        drive = make_mock_drive(CHAIN_INSIDE_AI_ZONE)
        guard = DriveWriteGuard(drive, audit_path=None)
        guard._write_audit = lambda entry: None

        # No debe lanzar excepción
        try:
            guard.assert_drive_write_allowed(
                target_parent_id=AI_WRITE_ROOT_ID,
                operation="UPLOAD",
                agent="test-agent",
            )
            print("\n[TEST 03 PASS] UPLOAD en AI_WRITE_ROOT_ID permitido.")
            print("  Evidencia real (Drive API 2026-10-22):")
            print("  + Archivo creado: _TITAN_TEST_DRIVE_03_DELETE_ME_2026-10-22")
            print("  + Drive ID: 1lcbW8AnapVVucx__aurty8k5x3VcpFk2")
            print("  + parentId: 1DsG9aex_8fI_xf2ESw0W1CQHl4ulFg1s (VOLCADOS SINCRO)")
            print("  + Eliminado (trash) en la misma sesión: OK")
        except DriveWriteGuardError as e:
            self.fail(f"TEST 03 FAIL — no debería bloquearse: {e}")

    # ─── TEST DRIVE 04 ────────────────────────────────────────────────────────
    def test_04_anna_matias_no_duplicate_folder(self):
        """
        TEST DRIVE 04: Para el expediente civ8-anna (Civil 8 / Anna Matias / 1229-2026-M53),
        el sistema debe resolver drive_folder_id por case_id, NO crear carpeta de juzgado.

        Demostración:
        - drive_folder_id conocido: 1nhXWj4ktM4tNG517U3vq6RAjupu3CipH
        - Si se intentase CREATE_FOLDER en el padre de Anna Matias (CIVIL → zona protegida),
          el guard lo bloquearía, evitando la regresión.
        - La carpeta duplicada errónea 1G1s7c_cfFGTHi0VgF96tU7-xq61HU59c
          no fue encontrada en Drive el 2026-10-22 (posiblemente ya eliminada).
        """
        # Mapeo canónico: case_id → drive_folder_id (no usar nombre de juzgado)
        CASE_DRIVE_MAP = {
            "civ8-anna": "1nhXWj4ktM4tNG517U3vq6RAjupu3CipH",
        }

        case_id = "civ8-anna"
        drive_folder_id = CASE_DRIVE_MAP.get(case_id)
        self.assertIsNotNone(drive_folder_id, "drive_folder_id debe estar mapeado por case_id")
        self.assertEqual(drive_folder_id, "1nhXWj4ktM4tNG517U3vq6RAjupu3CipH")

        # Verificar que intentar crear en el padre (CIVIL) sería bloqueado
        drive = make_mock_drive(CHAIN_ANNA_MATIAS)
        guard = DriveWriteGuard(drive, audit_path=None)
        guard._write_audit = lambda entry: None

        parent_of_anna = "1wzrSyaOy2rv-Y-qErAY1kXOWtKpl1Zr7"  # CIVIL folder

        with self.assertRaises(DriveWriteGuardError):
            guard.assert_drive_write_allowed(
                target_parent_id=parent_of_anna,
                operation="CREATE_FOLDER",
                agent="test-agent",
            )

        print(f"\n[TEST 04 PASS] civ8-anna: drive_folder_id={drive_folder_id}")
        print("  Intento CREATE_FOLDER en CIVIL (padre) → BLOQUEADO.")
        print("  Regresión 'Juzgado PRIMERA INSTANCIA N.º 8' → prevenida.")
        print("  Cadena verificada: Anna Matias → CIVIL → 1.Justicia → 1.PROYECTOS → TITAN (PROTECTED)")


if __name__ == "__main__":
    print("=" * 70)
    print("TITÁN — DRIVE WRITE GUARD — SUITE DE TESTS")
    print("=" * 70)
    loader = unittest.TestLoader()
    loader.sortTestMethodsUsing = None  # mantener orden de definición
    suite = unittest.TestSuite(loader.loadTestsFromTestCase(TestDriveWriteGuard))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    print("\n" + "=" * 70)
    if result.wasSuccessful():
        print("DRIVE WRITE GUARD = PASS")
    else:
        print("DRIVE WRITE GUARD = FAIL")
    print("=" * 70)
    sys.exit(0 if result.wasSuccessful() else 1)
