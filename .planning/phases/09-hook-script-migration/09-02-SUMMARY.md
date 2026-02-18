---
phase: 09-hook-script-migration
plan: 02
subsystem: observability
tags: [jsonl, hooks, pre-tool-use, pre-compact, extra-fields, ask-user-question]

requires:
  - phase: 08-jsonl-logging-foundation plan 02
    provides: write_hook_event_record() and deliver_async_with_logging() functions
provides:
  - Extended write_hook_event_record() with optional extra_fields_json parameter
  - Extended deliver_async_with_logging() with optional extra_fields_json passthrough
  - JSONL-emitting pre-tool-use-hook.sh with questions_forwarded field (ASK-04)
  - JSONL-emitting pre-compact-hook.sh with bidirectional support
affects: [phase-10 PostToolUse, phase-11 operational hardening]

tech-stack:
  added: []
  patterns: [jq --argjson for extra_fields merge, backward-compatible optional parameter via ${13:-}]

key-files:
  created: []
  modified:
    - lib/hook-utils.sh
    - tests/test-write-hook-event-record.sh
    - scripts/pre-tool-use-hook.sh
    - scripts/pre-compact-hook.sh

key-decisions:
  - "Option A chosen for ASK-04: dedicated questions_forwarded field via extra_fields_json parameter (not Option B wake_message reuse)"
  - "13th parameter defaults to empty via ${13:-} — existing 12-parameter call sites backward compatible"
  - "extra_fields_json merged into record via jq + $extra_fields at top level"

patterns-established:
  - "Pattern: optional extra_fields_json as last parameter with ${N:-} default"
  - "Pattern: jq -cn --argjson extra_fields for merging extra JSON into base record"
  - "Pattern: EXTRA_FIELDS_JSON built with jq -cn --arg before delivery call"

requirements-completed: [HOOK-13, HOOK-17, ASK-04]

duration: 3min
completed: 2026-02-18
---

# Plan 09-02: Extend Lib Functions and Migrate Medium Hooks Summary

**Extend JSONL functions with extra_fields_json, then migrate pre-tool-use-hook.sh (ASK-04) and pre-compact-hook.sh to structured JSONL**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-02-18
- **Completed:** 2026-02-18
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- write_hook_event_record() extended with optional 13th parameter extra_fields_json
- deliver_async_with_logging() extended with optional 11th parameter passed through to write_hook_event_record
- Existing 12-parameter call sites continue to work unchanged (backward compatible)
- pre-tool-use-hook.sh emits JSONL with trigger=ask_user_question, content_source=questions, and top-level questions_forwarded field (ASK-04 satisfied)
- pre-compact-hook.sh emits JSONL in both async and bidirectional paths
- Tests E (extra_fields merge), F (backward compatibility), G (final JSONL validity) added and passing
- All 54 test assertions pass across both test files
- All debug_log calls preserved

## Task Commits

1. **Task 0: Extend lib functions and add tests** - `d2ace58` (feat)
2. **Tasks 1-2: Migrate pre-tool-use and pre-compact hooks** - `04464b0` (feat)

## Files Created/Modified
- `lib/hook-utils.sh` - Extended write_hook_event_record (13th param) and deliver_async_with_logging (11th param)
- `tests/test-write-hook-event-record.sh` - Added Tests E, F, G for extra_fields_json coverage
- `scripts/pre-tool-use-hook.sh` - JSONL migration with questions_forwarded via extra_fields_json
- `scripts/pre-compact-hook.sh` - JSONL migration with bidirectional write_hook_event_record support

## Decisions Made
- Chose Option A (dedicated extra_fields_json parameter) over Option B (wake_message reuse) for ASK-04

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None.

---
*Phase: 09-hook-script-migration*
*Completed: 2026-02-18*
