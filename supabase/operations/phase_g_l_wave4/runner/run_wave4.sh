#!/bin/bash
# Phase G-N Wave 4: DEPRECATION SHIM
#
# Mission   : 2026-08-29-fleetconnect-operational-recovery
# Round     : r056 Phase G-N transactional / secret-safe / split-runner correction
#
# This file is INTENTIONALLY a hard deprecation error.
#
# Lux ee52b1a §5 BLOCKER: the old run_wave4.sh [import|import-and-apply]
#   single-script design re-executed PHASE 1's staging-create + COPY path on
#   the second invocation. The Founder's documented continuation
#   (`$0 import-and-apply`) therefore risked duplicate partner rows and
#   pre-mapping FK orphans before PHASE 2 ever began.
#
# G-N correction: the combined runner is GONE. There is no combined mode.
# PHASE 1 and PHASE 2 are two separate scripts that share no execution path:
#
#   ./run_wave4_import.sh     # PHASE 1: staging + transform import
#   ./run_wave4_apply.sh      # PHASE 2: legacy_user_id -> new_user_id apply
#
# PHASE 2 does NOT depend on PHASE 1's staging state; it only consumes the
# canonical public.* tables that PHASE 1 committed. PHASE 2 cannot re-trigger
# PHASE 1 because PHASE 2's heredoc never references staging.* or copies CSVs.
#
# If you reach this shim from the old runbook, STOP. Read
# evidence/r056-phase-g-n-founder-execution-runbook.md for the new sequence.

echo "FATAL: run_wave4.sh has been SPLIT in Phase G-N." >&2
echo "" >&2
echo "  Old: ./run_wave4.sh [import|import-and-apply]   <- REMOVED" >&2
echo "  New: ./run_wave4_import.sh                      <- PHASE 1 only" >&2
echo "  New: ./run_wave4_apply.sh                       <- PHASE 2 only" >&2
echo "" >&2
echo "See: supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-n-founder-execution-runbook.md" >&2
exit 70
