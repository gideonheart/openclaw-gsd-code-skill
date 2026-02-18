---
phase: 06-core-extraction-and-delivery-engine
plan: 01
subsystem: hooks
tags: [bash, jq, diff, flock, extraction, shared-library]

requires:
  - phase: 05-documentation
    provides: "Documented hook architecture with all 5 hook scripts"
provides:
  - "lib/hook-utils.sh with three DRY extraction functions for hook scripts"
  - "extract_last_assistant_response for transcript JSONL parsing"
  - "extract_pane_diff for flock-protected pane delta computation"
  - "format_ask_user_questions for AskUserQuestion tool_input formatting"
affects: [06-02, 06-03, stop-hook, pre-tool-use-hook]

tech-stack:
  added: []
  patterns:
    - "Source-based shared library (lib/*.sh sourced by hook entry points)"
    - "Type-filtered JSONL content selection (jq select over positional indexing)"
    - "fd-based flock in command group for atomic read-diff-write"

key-files:
  created:
    - "lib/hook-utils.sh"
  modified: []

key-decisions:
  - "Used printf '%s' instead of echo for all output to handle dash-prefixed and escape-containing values"
  - "Used command group { } with fd-based flock (200>lockfile) instead of subshell () for variable capture"
  - "Used process substitution <(printf '%s\\n' ...) for diff comparison to avoid stdin double-consumption"

patterns-established:
  - "Source-based library: lib/hook-utils.sh contains only function definitions, no side effects on source"
  - "Extraction fallback chain: transcript primary, pane diff fallback, tail baseline as last resort"

requirements-completed: [LIB-01, LIB-02, EXTRACT-03]

duration: 3min
completed: 2026-02-18
---

# Phase 6 Plan 01: Shared Library Summary

**lib/hook-utils.sh with three SRP extraction functions: transcript JSONL parsing via tail+jq type filtering, flock-protected pane diff with per-session /tmp state, and structured AskUserQuestion formatting**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-18T00:00:00Z
- **Completed:** 2026-02-18T00:03:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created lib/hook-utils.sh as side-effect-free sourceable bash library
- extract_last_assistant_response handles thinking/tool_use blocks via type-filtering (not positional indexing)
- extract_pane_diff uses flock-protected atomic read-diff-write cycle with per-session state in /tmp
- format_ask_user_questions formats structured JSON questions with numbered options and descriptions

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lib/hook-utils.sh with three extraction functions** - `59a0e35` (feat)

## Files Created/Modified
- `lib/hook-utils.sh` - Shared extraction functions sourced by stop-hook.sh and pre-tool-use-hook.sh

## Decisions Made
- Used printf instead of echo throughout to handle edge cases with dash-prefixed variables
- Used fd-based flock with command group (not subshell) to preserve variable capture for pane_delta
- Used process substitution for diff comparison to avoid stdin double-consumption issue

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- lib/hook-utils.sh ready for sourcing by Plan 06-02 (pre-tool-use-hook.sh) and Plan 06-03 (stop-hook.sh v2)
- All three functions verified: syntax check, function definition check, side-effect check, edge case handling

---
*Phase: 06-core-extraction-and-delivery-engine*
*Completed: 2026-02-18*
