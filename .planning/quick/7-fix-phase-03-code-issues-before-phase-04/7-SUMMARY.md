---
phase: 7-fix-phase-03-code-issues-before-phase-04
plan: 01
subsystem: queue
tags: [queue-processor, tui-driver, event-handlers, dry, safety]

# Dependency graph
requires:
  - phase: 03-stop-event-full-stack
    provides: queue-processor.mjs, tui-driver.mjs, event handlers built in Phase 03
provides:
  - writeQueueFileAtomically as named export from lib/queue-processor.mjs
  - resolveQueueFilePath as named export from lib/queue-processor.mjs
  - Both functions re-exported via lib/index.mjs
  - JSON.parse safety in all three Phase 03 event handlers
  - Absolute path to tui-driver.mjs in prompt_stop.md
affects: [04-pre-post-tool-use-handlers]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Shared atomic write helpers exported from lib module — never duplicated in bin scripts"
    - "Hook handlers guard JSON.parse with try/catch, exit 0 on malformed stdin"
    - "Prompt files use absolute paths for commands that run from external working directories"

key-files:
  created: []
  modified:
    - lib/queue-processor.mjs
    - lib/index.mjs
    - bin/tui-driver.mjs
    - events/stop/event_stop.mjs
    - events/session_start/event_session_start.mjs
    - events/user_prompt_submit/event_user_prompt_submit.mjs
    - events/stop/prompt_stop.md

key-decisions:
  - "writeQueueFileAtomically and resolveQueueFilePath promoted to named exports in lib/queue-processor.mjs — single source of truth"
  - "JSON.parse in hook handlers wrapped in try/catch with process.exit(0) on failure — hooks must never crash on bad input"
  - "prompt_stop.md uses absolute path to tui-driver.mjs — Gideon runs from openclaw workspace root, not skill directory"

patterns-established:
  - "Shared queue utilities live in lib/queue-processor.mjs and are imported via lib/index.mjs — bin scripts never re-implement them"
  - "All hook handler stdin parsing is guarded — exit 0 silently on parse failure"

requirements-completed: [DRY-01, SAFETY-01, PATH-01]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Quick Task 7: Fix Phase 03 Code Issues Before Phase 04 — Summary

**DRY violation fixed (writeQueueFileAtomically de-duplicated), all three hook handlers hardened against malformed stdin, and prompt_stop.md corrected to use absolute path to tui-driver.mjs**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T20:14:01Z
- **Completed:** 2026-02-20T20:16:00Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- Promoted `writeQueueFileAtomically` and `resolveQueueFilePath` to named exports in `lib/queue-processor.mjs` and added to `lib/index.mjs` barrel, then removed the local duplicate from `bin/tui-driver.mjs` (also removed `QUEUES_DIRECTORY`, `SKILL_ROOT`, and 5 now-unused imports)
- Wrapped `JSON.parse(rawStdin)` in try/catch with `process.exit(0)` on failure in all three event handlers (`event_stop.mjs`, `event_session_start.mjs`, `event_user_prompt_submit.mjs`) — hook handlers must never crash on bad input
- Fixed `events/stop/prompt_stop.md` command example to use absolute path `/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs` so it works from any working directory

## Task Commits

1. **Task 1: De-duplicate writeQueueFileAtomically and resolveQueueFilePath** - `294a8c2` (refactor)
2. **Task 2: Guard JSON.parse in all event handlers against malformed stdin** - `566b84a` (fix)
3. **Task 3: Fix relative path in prompt_stop.md to absolute path** - `8848b7a` (fix)

## Files Created/Modified

- `lib/queue-processor.mjs` - Added `export` keyword to `writeQueueFileAtomically` and `resolveQueueFilePath`
- `lib/index.mjs` - Added `writeQueueFileAtomically` and `resolveQueueFilePath` to barrel re-exports
- `bin/tui-driver.mjs` - Removed local duplicate functions/constants; consolidated to single import from `lib/index.mjs`
- `events/stop/event_stop.mjs` - JSON.parse guarded with try/catch
- `events/session_start/event_session_start.mjs` - JSON.parse guarded with try/catch
- `events/user_prompt_submit/event_user_prompt_submit.mjs` - JSON.parse guarded with try/catch
- `events/stop/prompt_stop.md` - Relative `bin/tui-driver.mjs` replaced with absolute path

## Decisions Made

None — plan executed exactly as specified. All changes were straightforward fixes with no architectural decisions required.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 03 code is clean and hardened — ready for Phase 04 (PreToolUse/PostToolUse AskUserQuestion handlers)
- No blockers or concerns

## Self-Check

**Files exist:**
- `lib/queue-processor.mjs`: export keywords added — FOUND
- `lib/index.mjs`: barrel includes writeQueueFileAtomically and resolveQueueFilePath — FOUND
- `bin/tui-driver.mjs`: no local writeQueueFileAtomically, no QUEUES_DIRECTORY, no SKILL_ROOT — VERIFIED
- `events/stop/event_stop.mjs`: JSON.parse in try/catch — FOUND
- `events/session_start/event_session_start.mjs`: JSON.parse in try/catch — FOUND
- `events/user_prompt_submit/event_user_prompt_submit.mjs`: JSON.parse in try/catch — FOUND
- `events/stop/prompt_stop.md`: absolute path present — FOUND

**Commits exist:**
- `294a8c2`: refactor(quick-7): de-duplicate — FOUND
- `566b84a`: fix(quick-7): guard JSON.parse — FOUND
- `8848b7a`: fix(quick-7): absolute path — FOUND

## Self-Check: PASSED

---
*Quick Task: 7-fix-phase-03-code-issues-before-phase-04*
*Completed: 2026-02-20*
