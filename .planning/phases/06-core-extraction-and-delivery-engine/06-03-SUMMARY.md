---
phase: 06-core-extraction-and-delivery-engine
plan: 03
subsystem: hooks
tags: [bash, jq, transcript, pane-diff, wake-format, v2]

requires:
  - phase: 06-core-extraction-and-delivery-engine
    provides: "lib/hook-utils.sh with extract_last_assistant_response and extract_pane_diff"
provides:
  - "stop-hook.sh with transcript extraction (primary) and pane diff fallback"
  - "v2 wake format with [CONTENT] replacing v1 [PANE CONTENT]"
  - "Clean break from v1 — no backward compatibility layer"
affects: [openclaw-agent-parsing, gideon-wake-handler, phase-7-deployment]

tech-stack:
  added: []
  patterns:
    - "Transcript-first content extraction with graceful degradation"
    - "v2 wake format: [SESSION IDENTITY], [TRIGGER], [CONTENT], [STATE HINT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS]"

key-files:
  created: []
  modified:
    - "scripts/stop-hook.sh"

key-decisions:
  - "v1 [PANE CONTENT] completely removed — clean break, no conditional toggle"
  - "PANE_CONTENT variable retained for state detection (section 8), context pressure (section 9), and pane diff fallback (section 9b)"
  - "Three-tier content fallback: transcript -> pane diff -> raw pane tail (if lib missing)"

patterns-established:
  - "Content extraction chain: transcript primary, pane diff fallback, raw tail ultimate fallback"
  - "v2 wake section ordering: SESSION IDENTITY, TRIGGER, CONTENT, STATE HINT, CONTEXT PRESSURE, AVAILABLE ACTIONS"

requirements-completed: [EXTRACT-01, EXTRACT-02, WAKE-07, WAKE-08]

duration: 3min
completed: 2026-02-18
---

# Phase 6 Plan 03: Stop Hook v2 Summary

**Stop hook upgraded with transcript JSONL extraction as primary content source, pane diff fallback, and v2 [CONTENT] wake format replacing v1 [PANE CONTENT]**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-18T00:06:00Z
- **Completed:** 2026-02-18T00:09:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added section 6b: source lib/hook-utils.sh with graceful degradation if missing
- Added section 7b: extract transcript_path from stdin JSON, call extract_last_assistant_response
- Added section 9b: three-tier content fallback (transcript -> pane diff -> raw pane tail)
- Replaced section 10: v2 wake format with [CONTENT] section, v1 [PANE CONTENT] completely removed
- Delivery section (11) unchanged — hybrid mode still supported

## Task Commits

Each task was committed atomically:

1. **Task 1: Add transcript extraction and pane diff fallback to stop-hook.sh** - `0bf21f2` (feat)

## Files Created/Modified
- `scripts/stop-hook.sh` - Modified with transcript extraction, pane diff fallback, and v2 wake format

## Decisions Made
- Clean break from v1: [PANE CONTENT] completely removed, no conditional v1/v2 toggle (WAKE-08)
- PANE_CONTENT kept for state detection and context pressure — these still need raw pane content
- Three-tier fallback ensures hook never crashes: transcript -> pane diff -> raw tail

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 6 complete — all three deliverables shipped (lib, pre-tool-use-hook, stop-hook v2)
- Phase 7 deployment gate: Gideon's wake message parsing must be updated before register-hooks.sh runs
- Format change from [PANE CONTENT] to [CONTENT] requires coordinated deployment

---
*Phase: 06-core-extraction-and-delivery-engine*
*Completed: 2026-02-18*
