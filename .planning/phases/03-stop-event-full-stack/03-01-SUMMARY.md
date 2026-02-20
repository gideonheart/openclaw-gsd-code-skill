---
phase: 03-stop-event-full-stack
plan: "01"
subsystem: lib
tags: [tmux, queue, tui, execFileSync, atomic-writes, event-driven]

# Dependency graph
requires:
  - phase: 02-shared-library
    provides: logger.mjs, paths.mjs, gateway.mjs, agent-resolver.mjs, index.mjs
  - phase: 02.1-refactor
    provides: refactored lib modules with correct patterns
provides:
  - lib/tui-common.mjs — typeCommandIntoTmuxSession() for tmux send-keys with Tab+Enter
  - lib/queue-processor.mjs — processQueueForHook, cancelQueueForSession, cleanupStaleQueueForSession
  - lib/index.mjs updated — all 9 exports from single import path
affects: [03-02-PLAN.md, 03-03-PLAN.md, bin/tui-driver.mjs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "execFileSync with argument arrays for tmux send-keys (no shell interpolation)"
    - "Tab completion for /gsd:* commands: type name, Tab, args, Enter"
    - "Atomic queue writes: writeFileSync(.tmp) + renameSync (POSIX-atomic, no flock)"
    - "Queue processor is hook-agnostic — same function called by all three event handlers"

key-files:
  created:
    - lib/tui-common.mjs
    - lib/queue-processor.mjs
  modified:
    - lib/index.mjs

key-decisions:
  - "typeCommandIntoTmuxSession splits /gsd:* commands at first space: command name gets Tab, then args typed separately"
  - "No explicit delays between tmux send-keys calls — execFileSync blocks until tmux returns, providing natural pacing"
  - "buildQueueCompleteSummary is internal helper — returns event/summary/commands payload for queue-complete agent wake"
  - "processQueueForHook returns action discriminants (no-queue, no-active-command, awaits-mismatch, advanced, queue-complete) — caller decides what to do"
  - "cancelQueueForSession returns completedCount/totalCount/remainingCommands — caller builds the agent notification"

patterns-established:
  - "typeCommandIntoTmuxSession: guard clauses throw, not return — must-not-silently-fail tmux ops"
  - "Queue processor never throws on missing queue — returns action object instead"
  - "All internal helpers are unexported functions in the same module (SRP without over-engineering)"

requirements-completed: [ARCH-04, TUI-02]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 03 Plan 01: Shared Lib Modules (tui-common + queue-processor) Summary

**tmux send-keys wrapper with Tab completion for /gsd:* and hook-agnostic queue processor with atomic writes for event-driven command sequencing**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T19:18:21Z
- **Completed:** 2026-02-20T19:20:06Z
- **Tasks:** 2
- **Files modified:** 3 (2 created, 1 updated)

## Accomplishments
- `lib/tui-common.mjs` exports `typeCommandIntoTmuxSession()` — handles /gsd:* Tab completion and plain /clear typing via execFileSync argument arrays
- `lib/queue-processor.mjs` exports three functions: processQueueForHook (advance/complete), cancelQueueForSession (stale rename + summary), cleanupStaleQueueForSession (startup archive)
- `lib/index.mjs` updated to re-export all 9 functions — 5 existing + 4 new

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lib/tui-common.mjs — tmux send-keys wrapper** - `9eba7de` (feat)
2. **Task 2: Create lib/queue-processor.mjs and update lib/index.mjs** - `7764769` (feat)

**Plan metadata:** (docs commit — see final_commit below)

## Files Created/Modified
- `lib/tui-common.mjs` - tmux send-keys wrapper with Tab completion for /gsd:* commands
- `lib/queue-processor.mjs` - queue read/advance/complete/cancel with atomic writes
- `lib/index.mjs` - re-exports 9 total functions (5 existing + 4 new from Phase 3)

## Decisions Made
- `typeCommandIntoTmuxSession` splits /gsd:* at the first space: command name gets Tab, arguments typed as plain text after Tab fires autocomplete
- No delays between tmux send-keys — execFileSync blocking provides natural pacing without artificial sleeps
- `processQueueForHook` returns discriminant action objects so callers can build appropriate notifications without knowing queue internals
- `cancelQueueForSession` returns full summary data (completedCount, totalCount, remainingCommands) — caller builds the agent wake message

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness
- Both shared modules ready for use by bin/tui-driver.mjs (Plan 03-02)
- All event handlers (stop, session_start, user_prompt_submit) can import from lib/index.mjs
- Queue processor is hook-agnostic — same processQueueForHook call works for all three handlers
- No blockers

## Self-Check: PASSED

All files verified present. All commits verified in git history.

- lib/tui-common.mjs: FOUND
- lib/queue-processor.mjs: FOUND
- 03-01-SUMMARY.md: FOUND
- Commit 9eba7de (tui-common.mjs): FOUND
- Commit 7764769 (queue-processor.mjs + index.mjs): FOUND

---
*Phase: 03-stop-event-full-stack*
*Completed: 2026-02-20*
