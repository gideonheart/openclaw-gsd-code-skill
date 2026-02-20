---
phase: quick-4
plan: 01
subsystem: docs
tags: [context, architecture, queue, tui-driver, stop-event]

requires:
  - phase: 03-stop-event-full-stack
    provides: "Phase 3 CONTEXT.md with Stop event architecture"

provides:
  - "Corrected queue schema (no trigger field)"
  - "Flag-based TUI driver call signature documented"
  - "All event handler filenames use .mjs extension"
  - "Queue-complete payload definition in Section 4"
  - "Queue-complete context note in Section 3 prompt"
  - "Hook registration moved into Phase 3 scope"
  - "UserPromptSubmit cancellation trade-off documented"
  - "idle_prompt retargeted to Phase 3.5"

affects: [03-stop-event-full-stack]

tech-stack:
  added: []
  patterns:
    - "Queue schema: id, command, status, awaits, result, completed_at — no trigger field"
    - "TUI driver: --session <name> flag + JSON array argument"
    - "All event handler entry points: .mjs extension (consistent with Phase 2)"

key-files:
  created: []
  modified:
    - .planning/phases/03-stop-event-full-stack/03-CONTEXT.md

key-decisions:
  - "TUI driver uses --session flag + JSON array string, not a JSON blob object argument"
  - "Queue-complete wake uses different prompt context than first-wake Stop — FYI, not decision"
  - "Hook registration is Phase 3 scope — phases must be self-contained and testable"
  - "UserPromptSubmit cancellation is aggressively conservative — any input cancels, simplicity wins"
  - "idle_prompt moved to Phase 3.5 — evaluate need after Phase 3 testing, not deferred to 4+"

requirements-completed: []

duration: 1min
completed: 2026-02-20
---

# Quick Task 4: Refactor Phase 3 CONTEXT.md with 8 Targeted Changes

**Phase 3 CONTEXT.md corrected with clean queue schema, flag-based TUI driver signature, .mjs extensions throughout, and queue-complete/hook-registration architecture fully defined**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-20T17:39:24Z
- **Completed:** 2026-02-20T17:41:16Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Removed redundant `trigger` field from queue schema — `awaits` is sufficient for queue processor logic
- Corrected TUI driver call signature to use `--session <name>` flag + JSON array argument in all 3 locations (Section 3 prompt, Section 4 description, Section 4 lifecycle creation step)
- Renamed all three event handler entry points from `.js` to `.mjs` in both Section 5 handler table and Section 6 file tree
- Added queue-complete payload JSON definition as a new subsection in Section 4 with agent context note
- Added queue-complete context subsection in Section 3 to clarify the agent receives a different prompt (not `prompt_stop.md`) after queue finishes
- Moved hook registration from deferred Phase 5 into Phase 3 scope with required entries and rationale
- Documented UserPromptSubmit cancellation trade-off — aggressive-by-design for Phase 3, future refinement noted
- Retargeted idle_prompt deferred item from Phase 4+ to Phase 3.5 with evaluation guidance

## Task Commits

Each task was committed atomically:

1. **Task 1: Apply all 8 targeted refactors to 03-CONTEXT.md** - `1156d2f` (docs)

## Files Created/Modified

- `.planning/phases/03-stop-event-full-stack/03-CONTEXT.md` - 8 surgical edits to clean up inaccuracies discovered in discuss-phase session

## Decisions Made

- TUI driver signature is `--session <name> '[...]'` — session name passed by gateway/orchestration layer, commands as JSON array string
- Queue-complete agent wake uses a different context than first-wake — FYI payload, not decision prompt — whether it needs its own prompt file is a Phase 3 implementation decision
- Hook registration is Phase 3 scope (not Phase 5) — handlers cannot be tested without registration, phases should be self-contained
- UserPromptSubmit cancellation: aggressive is better than subtle for Phase 3 — if human types anything, queue defers
- idle_prompt monitoring starts at Phase 3.5 — may emerge as a need during testing rather than being planned speculatively

## Deviations from Plan

None - plan executed exactly as written. The 8 refactors were applied as specified, using the user's exact instructions where they differed from plan wording (TUI driver signature format).

## Issues Encountered

None.

## Next Phase Readiness

- 03-CONTEXT.md is clean and accurate — Phase 3 planning can proceed with confidence
- All architecture decisions documented: queue schema, TUI driver API, handler filenames, hook registration scope
- Phase 3 planner has complete, non-contradictory spec to work from

---
*Quick Task: 4*
*Completed: 2026-02-20*
