---
phase: 06-core-extraction-and-delivery-engine
plan: 02
subsystem: hooks
tags: [bash, jq, pre-tool-use, ask-user-question, openclaw, async]

requires:
  - phase: 06-core-extraction-and-delivery-engine
    provides: "lib/hook-utils.sh with format_ask_user_questions function"
provides:
  - "scripts/pre-tool-use-hook.sh for AskUserQuestion forwarding to OpenClaw"
  - "v2 [ASK USER QUESTION] wake message format with structured questions, options, headers"
affects: [phase-7-registration, settings-json, openclaw-agent-parsing]

tech-stack:
  added: []
  patterns:
    - "Notification-only PreToolUse hook (always exit 0, never JSON to stdout)"
    - "Async-only openclaw delivery (always backgrounded, never foreground)"

key-files:
  created:
    - "scripts/pre-tool-use-hook.sh"
  modified: []

key-decisions:
  - "No bidirectional mode — AskUserQuestion forwarding is always async notification-only"
  - "No tool_name check in script — Claude Code matcher scoping handles filtering"
  - "Reused exact guard pattern from notification-idle-hook.sh for consistency"

patterns-established:
  - "PreToolUse hooks: always exit 0, never output JSON to stdout, always background openclaw"

requirements-completed: [ASK-01, ASK-02, ASK-03, WAKE-09]

duration: 3min
completed: 2026-02-18
---

# Phase 6 Plan 02: PreToolUse Hook Summary

**AskUserQuestion forwarding hook that extracts structured question data from PreToolUse stdin and delivers formatted [ASK USER QUESTION] wake messages to OpenClaw asynchronously**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-18T00:03:00Z
- **Completed:** 2026-02-18T00:06:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created scripts/pre-tool-use-hook.sh following established hook guard conventions
- Sources lib/hook-utils.sh and uses format_ask_user_questions for structured output
- Builds v2 [ASK USER QUESTION] wake message with questions, options, headers, multiSelect
- Always backgrounds openclaw call to avoid blocking TUI rendering
- Always exits 0 to never deny or block AskUserQuestion

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/pre-tool-use-hook.sh** - `d345369` (feat)

## Files Created/Modified
- `scripts/pre-tool-use-hook.sh` - PreToolUse hook for AskUserQuestion forwarding

## Decisions Made
- No bidirectional mode needed — AskUserQuestion forwarding is purely notification-only
- No tool_name check in script body — Claude Code matcher scoping handles this at registration level
- Reused exact guard pattern from notification-idle-hook.sh for consistency across hooks

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- pre-tool-use-hook.sh ready for Phase 7 registration (PreToolUse hook with AskUserQuestion matcher in settings.json)
- Hook registration is Phase 7 concern, not Phase 6

---
*Phase: 06-core-extraction-and-delivery-engine*
*Completed: 2026-02-18*
