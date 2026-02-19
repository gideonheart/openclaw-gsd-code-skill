---
phase: 16-hook-migration
plan: "02"
subsystem: hooks
tags: [bash, hooks, templates, load_hook_prompt, wake-message]

# Dependency graph
requires:
  - phase: 16-hook-migration-plan-01
    provides: "load_hook_prompt function in hook-utils.sh, prompt templates in scripts/prompts/"
provides:
  - "pre-compact-hook.sh loads pre-compact template via load_hook_prompt, emits [ACTION REQUIRED]"
  - "pre-tool-use-hook.sh loads ask-user-question template via load_hook_prompt, emits [ACTION REQUIRED]"
  - "post-tool-use-hook.sh loads answer-submitted template via load_hook_prompt, new [ACTION REQUIRED] section"
  - "session-end-hook.sh loads session-end template via load_hook_prompt, new [ACTION REQUIRED] section"
  - "All 7 hooks now use load_hook_prompt — zero hardcoded [AVAILABLE ACTIONS] blocks remain"
affects: [phase-17, hook-utils, hook-scripts]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "load_hook_prompt pattern: all 7 hooks load action prompts from scripts/prompts/ templates"
    - "[ACTION REQUIRED] header is consistent across all 7 hook wake messages"

key-files:
  created: []
  modified:
    - scripts/pre-compact-hook.sh
    - scripts/pre-tool-use-hook.sh
    - scripts/post-tool-use-hook.sh
    - scripts/session-end-hook.sh

key-decisions:
  - "post-tool-use and session-end hooks gain [ACTION REQUIRED] sections for consistency even though their templates say 'no action needed'"
  - "[ACTION REQUIRED] header placement: appended at end of WAKE_MESSAGE after [STATE HINT] for both new hooks"

patterns-established:
  - "All hook wake messages end with [ACTION REQUIRED] loaded from template — driver agent always has action context"

requirements-completed: [HOOK-21, HOOK-22, HOOK-23, HOOK-24]

# Metrics
duration: 2min
completed: 2026-02-19
---

# Phase 16 Plan 02: Hook Migration Summary

**All 7 hooks migrated to load_hook_prompt — [AVAILABLE ACTIONS] fully eliminated, pre-compact and pre-tool-use migrated, post-tool-use and session-end gained new [ACTION REQUIRED] sections**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-19T11:17:35Z
- **Completed:** 2026-02-19T11:19:35Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Replaced hardcoded [AVAILABLE ACTIONS] blocks in pre-compact-hook.sh and pre-tool-use-hook.sh with template-loaded [ACTION REQUIRED] sections
- Added new [ACTION REQUIRED] sections to post-tool-use-hook.sh and session-end-hook.sh, which previously had no action section
- Completed Phase 16 migration: all 7 hooks now use load_hook_prompt() with zero generic action blocks remaining

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate pre-compact-hook.sh and pre-tool-use-hook.sh** - `48dc16f` (feat)
2. **Task 2: Add [ACTION REQUIRED] to post-tool-use-hook.sh and session-end-hook.sh** - `cc4d8f8` (feat)

## Files Created/Modified

- `scripts/pre-compact-hook.sh` - Replaced [AVAILABLE ACTIONS] with load_hook_prompt "pre-compact" + [ACTION REQUIRED]
- `scripts/pre-tool-use-hook.sh` - Replaced [AVAILABLE ACTIONS] with load_hook_prompt "ask-user-question" + [ACTION REQUIRED]
- `scripts/post-tool-use-hook.sh` - Added load_hook_prompt "answer-submitted" + new [ACTION REQUIRED] section
- `scripts/session-end-hook.sh` - Added load_hook_prompt "session-end" + new [ACTION REQUIRED] section

## Decisions Made

- post-tool-use and session-end hooks gain [ACTION REQUIRED] sections for consistency even though their templates say "no action needed" — the [ACTION REQUIRED] header must still be present for consistency across all 7 hooks
- [ACTION REQUIRED] appended at end of WAKE_MESSAGE (after [STATE HINT]) for both newly-added hooks, matching the pattern from the plan specification

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 16 complete: all 7 hooks use load_hook_prompt(), zero [AVAILABLE ACTIONS] blocks remain
- Phase 17 can build on the complete hook migration baseline
- All prompts are now editable in scripts/prompts/ without touching hook scripts

---
*Phase: 16-hook-migration*
*Completed: 2026-02-19*
