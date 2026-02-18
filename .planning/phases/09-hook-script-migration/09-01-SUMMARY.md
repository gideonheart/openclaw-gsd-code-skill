---
phase: 09-hook-script-migration
plan: 01
subsystem: observability
tags: [jsonl, hooks, notification, session-end, migration]

requires:
  - phase: 08-jsonl-logging-foundation plan 02
    provides: deliver_async_with_logging() and write_hook_event_record() functions
provides:
  - JSONL-emitting notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh
affects: [phase-10 PostToolUse, phase-11 operational hardening]

tech-stack:
  added: []
  patterns: [lib source before guards, HOOK_ENTRY_MS after stdin, JSONL_FILE alongside GSD_HOOK_LOG, deliver_async_with_logging for async, write_hook_event_record for bidirectional]

key-files:
  created: []
  modified:
    - scripts/notification-idle-hook.sh
    - scripts/notification-permission-hook.sh
    - scripts/session-end-hook.sh

key-decisions:
  - "Source lib/hook-utils.sh at top of script before any guard exit — established as the Phase 9 migration pattern"
  - "HOOK_ENTRY_MS placed after STDIN_JSON=$(cat) to measure processing time, not process startup"
  - "JSONL_FILE assigned alongside GSD_HOOK_LOG in Phase 2 redirect block"
  - "Notification hooks have bidirectional branch needing write_hook_event_record() with outcome=sync_delivered"
  - "session-end-hook.sh always async with STATE=terminated, CONTENT_SOURCE=none"

patterns-established:
  - "Pattern: 5-change migration (source top, HOOK_ENTRY_MS, JSONL_FILE, delete mid-script source, replace delivery)"
  - "Pattern: bidirectional branches use write_hook_event_record() directly with outcome=sync_delivered"
  - "Pattern: async branches use deliver_async_with_logging() — hook exits immediately"

requirements-completed: [HOOK-14, HOOK-15, HOOK-16]

duration: 3min
completed: 2026-02-18
---

# Plan 09-01: Migrate Simple Hooks to JSONL Summary

**Migrate notification-idle-hook.sh, notification-permission-hook.sh, and session-end-hook.sh to emit structured JSONL records**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-02-18
- **Completed:** 2026-02-18
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- All three hooks source lib/hook-utils.sh before any guard exit (line 22, first exit at line 25)
- HOOK_ENTRY_MS captures timing after stdin consumption in each hook
- JSONL_FILE assigned alongside GSD_HOOK_LOG in Phase 2 redirect block
- Notification hooks use deliver_async_with_logging (async) and write_hook_event_record (bidirectional)
- session-end-hook.sh uses deliver_async_with_logging with trigger=session_end, state=terminated, content_source=none
- All existing debug_log calls preserved — plain-text .log files continue in parallel
- Guard exits do NOT emit JSONL records
- Mid-script LIB_PATH source blocks removed (no double-sourcing)

## Task Commits

1. **Tasks 1-2: Migrate all three simple hooks** - `38683c9` (feat)

## Files Created/Modified
- `scripts/notification-idle-hook.sh` - JSONL migration with trigger=idle_prompt, content_source=pane
- `scripts/notification-permission-hook.sh` - JSONL migration with trigger=permission_prompt, content_source=pane
- `scripts/session-end-hook.sh` - JSONL migration with trigger=session_end, state=terminated, content_source=none

## Decisions Made
None - followed plan as specified.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None.

---
*Phase: 09-hook-script-migration*
*Completed: 2026-02-18*
