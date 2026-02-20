---
phase: 03-stop-event-full-stack
plan: "02"
subsystem: events
tags: [stop-hook, tui-driver, queue, tmux, gateway, eslm, event-handler]

# Dependency graph
requires:
  - phase: 03-stop-event-full-stack
    plan: "01"
    provides: lib/tui-common.mjs, lib/queue-processor.mjs, lib/index.mjs (9 exports)
  - phase: 02-shared-library
    provides: gateway.mjs, agent-resolver.mjs, logger.mjs
provides:
  - events/stop/event_stop.mjs — Stop hook entry point with queue and fresh-wake logic
  - events/stop/prompt_stop.md — Agent decision prompt for Stop events
  - bin/tui-driver.mjs — Generic TUI driver that creates queue and types first command
affects: [03-03-PLAN.md, settings.json hook registration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stop handler reads sessionName via tmux display-message -p '#S' (not hook payload session_id)"
    - "Queue-complete path: JSON.stringify(result.summary) as messageContent, reuses prompt_stop.md"
    - "TUI driver uses parseArgs from node:util with allowPositionals for JSON command array"
    - "Atomic queue write: writeFileSync(.tmp) + renameSync — same pattern as queue-processor.mjs"
    - "resolveAwaitsForCommand: /clear -> SessionStart+clear, all others -> Stop+null (safe default)"

key-files:
  created:
    - events/stop/event_stop.mjs
    - events/stop/prompt_stop.md
    - bin/tui-driver.mjs

key-decisions:
  - "Queue-complete reuses prompt_stop.md (not a separate prompt file) — prompt already has 'When to do nothing' covering this case"
  - "sessionName resolved via tmux display-message -p '#S' at handler runtime — not from hook payload session_id (which is a UUID)"
  - "TUI driver resolveAwaitsForCommand: /clear -> SessionStart+clear, /gsd:* and unknown -> Stop+null (safe default)"

patterns-established:
  - "Stop handler: read stdin JSON, guard stop_hook_active, resolve session via tmux, guard agent, guard empty message, check queue, fresh-wake"
  - "TUI driver: parseArgs positional for JSON array, build queue with awaits, write atomic, type first command, exit"

requirements-completed: [STOP-01, STOP-02, STOP-03, TUI-01, TUI-05]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 03 Plan 02: Stop Handler + TUI Driver Summary

**Stop hook handler with queue-or-wake branching, agent decision prompt, and generic TUI driver that creates a command queue and types the first command into tmux**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T19:23:19Z
- **Completed:** 2026-02-20T19:25:41Z
- **Tasks:** 2
- **Files modified:** 3 (all created)

## Accomplishments
- `events/stop/event_stop.mjs` — complete Stop hook handler: guards stop_hook_active, resolves session via tmux, guards agent/empty message, delegates to processQueueForHook when queue exists, fresh-wakes agent with last_assistant_message + extracted suggested commands
- `events/stop/prompt_stop.md` — agent decision prompt matching CONTEXT.md Section 3 structure exactly, instructs agent to call bin/tui-driver.mjs
- `bin/tui-driver.mjs` — executable TUI driver: parses --session + JSON command array, builds queue with per-command awaits, writes atomically, types first command via typeCommandIntoTmuxSession, exits

## Task Commits

Each task was committed atomically:

1. **Task 1: Create events/stop/event_stop.mjs and events/stop/prompt_stop.md** - `e419df8` (feat)
2. **Task 2: Create bin/tui-driver.mjs — generic TUI command driver** - `671784d` (feat)

**Plan metadata:** (docs commit — see final_commit below)

## Files Created/Modified
- `events/stop/event_stop.mjs` - Stop hook handler: stdin JSON parsing, guards, queue delegation, fresh-wake path
- `events/stop/prompt_stop.md` - Agent decision prompt: what to do, command types, when to do nothing
- `bin/tui-driver.mjs` - Generic TUI driver: queue creation with awaits mapping, atomic write, types first command

## Decisions Made
- Queue-complete path reuses `prompt_stop.md` rather than a separate prompt file — the "When to do nothing" and "If you received a queue-complete summary" guidance already covers this case, keeping prompt count minimal
- `sessionName` resolved at handler runtime via `tmux display-message -p '#S'` — Claude Code's `session_id` in the hook payload is a UUID, not the tmux session name
- `resolveAwaitsForCommand` in tui-driver: `/clear` maps to `SessionStart+clear`, everything else maps to `Stop+null` (safe default that works for all /gsd:* commands and unknown commands)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness
- Stop handler and TUI driver ready for use by Plan 03-03
- Plan 03-03 delivers: event_session_start.mjs, event_user_prompt_submit.mjs, and hook registration in settings.json
- No blockers — all shared lib modules (Phase 03-01) and gateway/agent-resolver (Phase 02) available

## Self-Check: PASSED

All files verified present. All commits verified in git history.

- events/stop/event_stop.mjs: FOUND
- events/stop/prompt_stop.md: FOUND
- bin/tui-driver.mjs: FOUND
- Commit e419df8 (event_stop + prompt_stop): FOUND
- Commit 671784d (tui-driver): FOUND

---
*Phase: 03-stop-event-full-stack*
*Completed: 2026-02-20*
