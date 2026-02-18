---
phase: 11-operational-hardening
plan: 02
subsystem: infra
tags: [bash, jq, jsonl, diagnostics, diagnose-hooks]

# Dependency graph
requires:
  - phase: 09-hook-script-migration
    provides: per-session JSONL log files with structured records (timestamp, hook_script, trigger, outcome, duration_ms)
provides:
  - scripts/diagnose-hooks.sh: Step 10 JSONL Log Analysis with jq-based diagnostic queries (recent events, outcome distribution, hook distribution, non-delivered detection, duration stats)
affects:
  - operational-debugging (operators can now assess hook health from structured JSONL data)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "jq -r @tsv for tabular JSONL output in diagnostic scripts"
    - "jq -s slurp for aggregate statistics (min, max, avg) across JSONL records"
    - "jq -c select() for filtering JSONL records by field value"

key-files:
  created: []
  modified:
    - scripts/diagnose-hooks.sh

key-decisions:
  - "Step 10 inserted between existing Step 9 (Hook Debug Logs) and optional test-wake (renumbered to Step 11)"
  - "Missing JSONL file handled as INFO not FAIL — fresh installs have not fired hooks yet"
  - "Non-delivered events trigger FAIL with last 5 error details — operational alerting pattern"
  - "All jq expressions in single quotes to prevent shell interpretation of != operator"

patterns-established:
  - "Pattern: JSONL_LOG_FILE derived from HOOK_LOG and TMUX_SESSION_NAME — same pattern as .log files"
  - "Pattern: Non-delivered check as separate TOTAL_CHECKS increment — mirrors existing pass/fail accounting"

requirements-completed: [OPS-03]

# Metrics
duration: 2min
completed: 2026-02-18
---

# Phase 11 Plan 02: diagnose-hooks.sh JSONL Log Analysis Summary

**JSONL-aware diagnostics showing recent hook events, outcome distribution, error detection, and duration stats via jq queries in diagnose-hooks.sh Step 10**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-18T13:55:00Z
- **Completed:** 2026-02-18T13:57:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Added Step 10 (JSONL Log Analysis) to `diagnose-hooks.sh` with 5 diagnostic subsections: recent events, outcome distribution, hook script distribution, non-delivered event detection, and duration stats
- Renumbered optional test-wake from Step 10 to Step 11
- Updated usage help text to include JSONL log analysis step
- Verified end-to-end against live warden session — 22/22 checks passed including new JSONL analysis

## Task Commits

Both tasks committed atomically:

1. **Task 1+2: JSONL analysis and help text update** - `b6f56c9` (feat)

## Files Created/Modified

- `scripts/diagnose-hooks.sh` - Added Step 10 JSONL Log Analysis with jq queries for recent events (@tsv), outcome distribution (sort | uniq -c), hook script distribution, non-delivered event detection (select != delivered), and duration stats (jq -s slurp with min/max/avg). Renumbered test-wake to Step 11. Updated usage help text.

## Decisions Made

None - followed plan as specified.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - diagnose-hooks.sh is self-contained. The new Step 10 activates automatically when JSONL log files exist.

## Next Phase Readiness

- Phase 11 is the final phase of v3.0 milestone
- All v3.0 requirements (JSONL-01 through JSONL-05, HOOK-12 through HOOK-17, ASK-04 through ASK-06, OPS-01 through OPS-03) are complete
- logrotate config needs one-time installation via `scripts/install-logrotate.sh` (user setup)

---
*Phase: 11-operational-hardening*
*Completed: 2026-02-18*
