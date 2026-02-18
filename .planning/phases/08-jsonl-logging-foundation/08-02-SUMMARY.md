---
phase: 08-jsonl-logging-foundation
plan: 02
subsystem: observability
tags: [jsonl, openclaw, async, background-subshell, bash, logging]

requires:
  - phase: 08-jsonl-logging-foundation plan 01
    provides: write_hook_event_record() function for JSONL record writing
provides:
  - deliver_async_with_logging() wrapper for async openclaw delivery with JSONL logging
  - Integration test proving async pipeline works with mocked openclaw
affects: [phase-09 hook migration]

tech-stack:
  added: []
  patterns: [background subshell with </dev/null, mock openclaw via bash function override, export -f for subshell function visibility]

key-files:
  created:
    - tests/test-deliver-async-with-logging.sh
  modified:
    - lib/hook-utils.sh

key-decisions:
  - "10 explicit positional parameters — response and outcome determined inside the background subshell"
  - "export -f openclaw in tests for subshell visibility of mock"
  - "sleep 2 wait in tests for background subshell completion — production hooks do not wait"

patterns-established:
  - "Pattern: (openclaw ... 2>&1) || true inside background subshell for response capture"
  - "Pattern: openclaw mock via bash function for isolated testing"
  - "Pattern: deliver_async_with_logging replaces bare openclaw ... & in Phase 9 migration"

requirements-completed: [JSONL-05]

duration: 3min
completed: 2026-02-18
---

# Plan 08-02: deliver_async_with_logging() Summary

**Async delivery wrapper in lib/hook-utils.sh with background subshell, openclaw response capture, and JSONL record writing via write_hook_event_record()**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-02-18
- **Completed:** 2026-02-18
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- deliver_async_with_logging() function appended to lib/hook-utils.sh with 10 explicit parameters
- Background subshell with explicit </dev/null to prevent stdin inheritance hangs from Claude Code's pipe
- openclaw response captured inside subshell, outcome determined (delivered / no_response)
- write_hook_event_record() called from inside subshell with full lifecycle data
- Calling hook exits immediately — no wait for background subshell
- Integration test with mocked openclaw verifying: successful delivery, failed delivery, special characters
- No regression: Plan 08-01 tests still pass, all 6 functions defined

## Task Commits

Each task was committed atomically:

1. **Task 1: Add deliver_async_with_logging() function** - `d231ef6` (feat)
2. **Task 2: Create integration test** - `10cc77d` (test)

## Files Created/Modified
- `lib/hook-utils.sh` - Added deliver_async_with_logging() function (53 lines)
- `tests/test-deliver-async-with-logging.sh` - Integration test with mocked openclaw (173 lines, executable)

## Decisions Made
None - followed plan as specified.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both Phase 8 functions ready for Phase 9 hook script migration
- Phase 9 will replace bare `openclaw ... &` with `deliver_async_with_logging()` in all 6 hook scripts
- Phase 9 will add `HOOK_ENTRY_MS=$(date +%s%3N)` and `JSONL_FILE` to each hook script

---
*Phase: 08-jsonl-logging-foundation*
*Completed: 2026-02-18*
