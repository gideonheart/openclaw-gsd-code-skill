---
phase: 16-hook-migration
plan: "01"
subsystem: hooks
tags: [bash, hooks, templates, load_hook_prompt, wake-message]

# Dependency graph
requires:
  - phase: 15-hook-templates
    provides: "load_hook_prompt() function in lib/hook-utils.sh and scripts/prompts/*.md template files"
provides:
  - "stop-hook.sh emits [ACTION REQUIRED] via response-complete template"
  - "notification-idle-hook.sh emits [ACTION REQUIRED] via idle-prompt template"
  - "notification-permission-hook.sh emits [ACTION REQUIRED] via permission-prompt template"
  - "Zero [AVAILABLE ACTIONS] occurrences across all three hooks"
affects:
  - "16-hook-migration (plans 02+)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hook wake messages use [ACTION REQUIRED] (not [AVAILABLE ACTIONS]) with template-loaded content"
    - "MENU_DRIVER_PATH and SCRIPT_DIR set as local vars before WAKE_MESSAGE construction"
    - "ACTION_PROMPT=$(load_hook_prompt <name> ...) pattern for all three hooks"

key-files:
  created: []
  modified:
    - scripts/stop-hook.sh
    - scripts/notification-idle-hook.sh
    - scripts/notification-permission-hook.sh

key-decisions:
  - "Template name per hook: stop-hook uses response-complete, idle-hook uses idle-prompt, permission-hook uses permission-prompt"
  - "ACTION_PROMPT computed before WAKE_MESSAGE heredoc — clean separation of template loading and message construction"

patterns-established:
  - "load_hook_prompt insertion point: three lines (MENU_DRIVER_PATH, SCRIPT_DIR, ACTION_PROMPT) before WAKE_MESSAGE construction"
  - "[ACTION REQUIRED] replaces [AVAILABLE ACTIONS] as the action section label across all three hooks"

requirements-completed: [HOOK-18, HOOK-19, HOOK-20]

# Metrics
duration: 2min
completed: 2026-02-19
---

# Phase 16 Plan 01: Hook Migration Summary

**Three hooks migrated from hardcoded [AVAILABLE ACTIONS] to template-loaded [ACTION REQUIRED] via load_hook_prompt(), giving each trigger context its own tailored command set**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-19T11:17:28Z
- **Completed:** 2026-02-19T11:18:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- stop-hook.sh now loads response-complete.md template for [ACTION REQUIRED] section
- notification-idle-hook.sh now loads idle-prompt.md template for [ACTION REQUIRED] section
- notification-permission-hook.sh now loads permission-prompt.md template for [ACTION REQUIRED] section
- Zero occurrences of [AVAILABLE ACTIONS] remain across all three hook scripts
- All three scripts pass bash -n syntax check

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate stop-hook.sh to load_hook_prompt("response-complete")** - `4609e57` (feat)
2. **Task 2: Migrate notification-idle-hook.sh and notification-permission-hook.sh** - `86c3054` (feat)

**Plan metadata:** (docs commit - see below)

## Files Created/Modified

- `scripts/stop-hook.sh` - Added MENU_DRIVER_PATH, SCRIPT_DIR, ACTION_PROMPT vars; replaced [AVAILABLE ACTIONS] with [ACTION REQUIRED] + ${ACTION_PROMPT}
- `scripts/notification-idle-hook.sh` - Same pattern, loads idle-prompt template
- `scripts/notification-permission-hook.sh` - Same pattern, loads permission-prompt template

## Decisions Made

- Template name mapping is explicit in each hook (response-complete, idle-prompt, permission-prompt) — each hook controls its own context
- Three setup lines (MENU_DRIVER_PATH, SCRIPT_DIR, ACTION_PROMPT) added immediately before WAKE_MESSAGE heredoc to keep setup adjacent to usage

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three primary hooks migrated — Phase 16 Plan 01 complete
- Plan 02 (if any) can proceed with remaining hook migrations
- All hooks will now serve trigger-specific command guidance to the driving agent

---
*Phase: 16-hook-migration*
*Completed: 2026-02-19*

## Self-Check: PASSED

- scripts/stop-hook.sh: FOUND
- scripts/notification-idle-hook.sh: FOUND
- scripts/notification-permission-hook.sh: FOUND
- 16-01-SUMMARY.md: FOUND
- Commit 4609e57: FOUND
- Commit 86c3054: FOUND
