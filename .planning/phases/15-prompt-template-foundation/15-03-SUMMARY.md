---
phase: 15-prompt-template-foundation
plan: 03
subsystem: hooks
tags: [bash, prompt-templates, hook-prompts, tui]

requires:
  - phase: 15-prompt-template-foundation
    provides: load_hook_prompt() function and menu-driver multi-select actions
provides:
  - 7 per-hook prompt template files in scripts/prompts/
affects: [phase-16-hook-migration, phase-17-documentation]

tech-stack:
  added: []
  patterns: [per-hook prompt templates with placeholder variables]

key-files:
  created:
    - scripts/prompts/response-complete.md
    - scripts/prompts/ask-user-question.md
    - scripts/prompts/idle-prompt.md
    - scripts/prompts/permission-prompt.md
    - scripts/prompts/pre-compact.md
    - scripts/prompts/session-end.md
    - scripts/prompts/answer-submitted.md
  modified: []

key-decisions:
  - "Each template lists only commands relevant to its trigger context"
  - "answer-submitted.md is purely informational with no TUI commands"
  - "session-end.md references spawn.sh for restart, not menu-driver (session is dead)"

patterns-established:
  - "Template format: brief context line followed by labeled command list"
  - "No markdown headers in templates — plain text embedded in wake messages"
  - "Multi-select instructions documented as separate section in ask-user-question.md"

requirements-completed: [PROMPT-02, PROMPT-03, PROMPT-04, PROMPT-05, PROMPT-06, PROMPT-07, PROMPT-08]

duration: 2min
completed: 2026-02-19
---

# Plan 15-03: Prompt Template Files Summary

**7 per-hook prompt templates created with context-specific command subsets replacing generic all-commands listing**

## Performance

- **Duration:** 2 min
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Created all 7 template files in scripts/prompts/
- Each template contains only commands relevant to its trigger type
- ask-user-question.md includes explicit multi-select checkbox navigation (arrow_up, arrow_down, space, enter)
- answer-submitted.md is informational-only with zero TUI commands
- session-end.md references spawn.sh for session restart instead of menu-driver
- All templates use {SESSION_NAME}, {MENU_DRIVER_PATH}, {SCRIPT_DIR} placeholders

## Task Commits

1. **Task 1: response-complete, idle-prompt, permission-prompt** - `05fa1c1` (feat)
2. **Task 2: ask-user-question, pre-compact, session-end, answer-submitted** - `f6c4764` (feat)

## Files Created/Modified
- `scripts/prompts/response-complete.md` - Stop-hook: snapshot/type/enter/esc/clear_then
- `scripts/prompts/idle-prompt.md` - Idle-hook: snapshot/type/enter/clear_then
- `scripts/prompts/permission-prompt.md` - Permission-hook: snapshot/choose/enter/esc
- `scripts/prompts/ask-user-question.md` - Pre-tool-use: choose/arrows/space/type/snapshot
- `scripts/prompts/pre-compact.md` - Pre-compact: snapshot/clear_then (informational)
- `scripts/prompts/session-end.md` - Session-end: spawn.sh restart reference
- `scripts/prompts/answer-submitted.md` - Post-tool-use: informational only

## Decisions Made
- Used plain text format (no markdown headers) since templates are embedded in wake messages
- Grouped multi-select instructions as a separate labeled section in ask-user-question.md

## Deviations from Plan
None - plan executed exactly as written

## Issues Encountered
None

## Next Phase Readiness
- All 7 templates ready for Phase 16 hook migration (replace [AVAILABLE ACTIONS] with load_hook_prompt() calls)

---
*Phase: 15-prompt-template-foundation*
*Completed: 2026-02-19*
