---
phase: 03-stop-event-full-stack
plan: "03"
subsystem: events
tags: [claude-code-hooks, session-start, user-prompt-submit, queue-processor, event-handlers]

# Dependency graph
requires:
  - phase: 03-01
    provides: lib/queue-processor.mjs with processQueueForHook, cancelQueueForSession, cleanupStaleQueueForSession
  - phase: 03-02
    provides: events/stop/event_stop.mjs and prompt_stop.md as pattern reference
provides:
  - events/session_start/event_session_start.mjs — SessionStart hook handler for /clear advance and startup stale cleanup
  - events/user_prompt_submit/event_user_prompt_submit.mjs — UserPromptSubmit hook handler for queue cancellation on manual input
  - README.md Hook Registration section — manual settings.json entries for Stop, SessionStart, UserPromptSubmit
affects:
  - phase-04
  - phase-05

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Shared prompt reuse — session_start and user_prompt_submit both reuse events/stop/prompt_stop.md via relative path resolve
    - Thin handler pattern — all branch logic is guard clauses; majority of logic lives in lib/queue-processor.mjs
    - Path resolution for cross-event prompt — resolve(dirname(fileURLToPath(import.meta.url)), '..', 'stop', 'prompt_stop.md')

key-files:
  created:
    - events/session_start/event_session_start.mjs
    - events/user_prompt_submit/event_user_prompt_submit.mjs
  modified:
    - README.md

key-decisions:
  - "SessionStart and UserPromptSubmit reuse prompt_stop.md — no dedicated prompts needed for pure queue-advance handlers per CONTEXT.md Section 3"
  - "UserPromptSubmit stdin payload is parsed but unused — session resolved via tmux display-message, consistent with Stop and SessionStart"

patterns-established:
  - "Cross-event prompt reuse: resolve relative to __dirname, navigate to ../stop/prompt_stop.md"
  - "Guard-first handler structure: sessionName empty -> exit 0, resolvedAgent null -> exit 0, then business logic"

requirements-completed:
  - ARCH-04

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 03 Plan 03: SessionStart + UserPromptSubmit Handlers Summary

**SessionStart and UserPromptSubmit queue lifecycle handlers completing the Phase 3 event-driven architecture, with hook registration documented in README.md**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T19:27:51Z
- **Completed:** 2026-02-20T19:29:41Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- SessionStart handler advances queue on source:clear and archives stale queues on source:startup, waking agent in both cases when action is taken
- UserPromptSubmit handler cancels active queue when user types manually, waking agent with completed/remaining command summary
- README.md Hook Registration section documents all three settings.json entries (Stop 30s, SessionStart 30s, UserPromptSubmit 10s) with absolute path placeholders

## Task Commits

Each task was committed atomically:

1. **Task 1: Create events/session_start/event_session_start.mjs** - `fa1d3cd` (feat)
2. **Task 2: Create events/user_prompt_submit/event_user_prompt_submit.mjs** - `616c1d4` (feat)
3. **Task 3: Document manual hook registration in README.md** - `74ddc98` (docs)

**Plan metadata:** _(docs commit to follow)_

## Files Created/Modified
- `events/session_start/event_session_start.mjs` - SessionStart hook handler; source:clear advances queue, source:startup archives stale queues
- `events/user_prompt_submit/event_user_prompt_submit.mjs` - UserPromptSubmit hook handler; cancels queue on manual input, wakes agent with cancellation summary
- `README.md` - Hook Registration section with settings.json entries for all three Phase 3 handlers

## Decisions Made
- Both handlers reuse `events/stop/prompt_stop.md` — no dedicated prompt files needed for pure queue-advance handlers per CONTEXT.md Section 3
- UserPromptSubmit reads stdin (required by Claude Code hook contract) but uses tmux display-message for session name, consistent with other handlers

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

Manual: Add the three hook entries from the README.md Hook Registration section to `~/.claude/settings.json`. Phase 5 will automate this.

## Next Phase Readiness
- Phase 3 is now complete: Stop, SessionStart, and UserPromptSubmit handlers all built and tested for syntax
- Queue lifecycle is fully implemented: create (TUI driver), advance (Stop/SessionStart), cancel (UserPromptSubmit), stale cleanup (SessionStart startup)
- Phase 4 can begin: PreToolUse/PostToolUse for AskUserQuestion closed-loop control

## Self-Check: PASSED

All files verified present. All commits verified in git log.

---
*Phase: 03-stop-event-full-stack*
*Completed: 2026-02-20*
