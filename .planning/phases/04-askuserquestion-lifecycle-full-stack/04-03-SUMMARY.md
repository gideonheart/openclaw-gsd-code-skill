---
phase: 04-askuserquestion-lifecycle-full-stack
plan: 03
subsystem: events
tags: [post-tool-use, ask-user-question, verification, gateway, tui-driver]

# Dependency graph
requires:
  - phase: 04-01
    provides: lib/ask-user-question.mjs with compareAnswerWithIntent, readPendingAnswer, deletePendingAnswer, deleteQuestionMetadata
  - phase: 04-02
    provides: bin/tui-driver-ask.mjs and savePendingAnswer — the TUI driver that creates pending-answer files
provides:
  - PostToolUse router dispatching AskUserQuestion to verification handler
  - AskUserQuestion PostToolUse verification handler closing the PreToolUse -> PostToolUse loop
  - Mismatch correction prompt instructing agent to correct on next AskUserQuestion
affects:
  - Phase 05 (any future hook events that need PostToolUse verification pattern)
  - settings.json (needs PostToolUse event registered for event_post_tool_use.mjs)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PostToolUse router mirrors PreToolUse router exactly — same structure, same guard pattern"
    - "3-path verification: match (silent), mismatch (wake), missing file (warn+heal)"
    - "Both metadata files deleted on ALL paths — no cleanup debt"
    - "buildMismatchMessageContent is a private SRP helper — one job, not in handler"

key-files:
  created:
    - events/post_tool_use/event_post_tool_use.mjs
    - events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs
    - events/post_tool_use/ask_user_question/prompt_post_ask_mismatch.md
  modified: []

key-decisions:
  - "PostToolUse router is a structural mirror of PreToolUse router — same readHookContext + dispatch-by-tool_name pattern, ensures consistent extension path"
  - "buildMismatchMessageContent extracted as private SRP helper — handler stays thin, formatting logic separated"
  - "formatQuestionsForMismatchContext handles missing/malformed toolInput gracefully — returns placeholder string, never throws"

patterns-established:
  - "PostToolUse handler: thin plumbing — guard clauses, early returns, domain logic in lib"
  - "Mismatch notification: messageContent (structured data) + promptFilePath (instructions) combined by gateway"
  - "Both files deleted on all 3 paths — match, mismatch, missing — no conditional cleanup"

requirements-completed: [ASK-03, ASK-04]

# Metrics
duration: 2min
completed: 2026-02-22
---

# Phase 04 Plan 03: PostToolUse AskUserQuestion Verification Summary

**PostToolUse router + 3-path verification handler closing the AskUserQuestion PreToolUse -> PostToolUse loop with silent match (zero tokens) or agent wake on mismatch**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-22T11:52:11Z
- **Completed:** 2026-02-22T11:53:57Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- PostToolUse router built (event_post_tool_use.mjs) mirroring PreToolUse router structure exactly
- AskUserQuestion PostToolUse verification handler implementing all 3 CONTEXT.md outcomes: match (silent + cleanup), mismatch (wake agent with details + cleanup), missing file (warn + cleanup)
- Mismatch correction prompt created with actionable instructions for the agent

## Task Commits

Each task was committed atomically:

1. **Task 1: PostToolUse router and AskUserQuestion verification handler** - `1e324ed` (feat)
2. **Task 2: PostToolUse mismatch correction prompt** - `21e7f23` (feat)

**Plan metadata:** (see final commit below)

## Files Created/Modified
- `events/post_tool_use/event_post_tool_use.mjs` - PostToolUse hook entry point, dispatches by tool_name
- `events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs` - Verification handler: reads pending answer, compares with tool_response, handles 3 outcomes
- `events/post_tool_use/ask_user_question/prompt_post_ask_mismatch.md` - Agent prompt for mismatch correction, instructs via Chat or Type on next question

## Decisions Made
- buildMismatchMessageContent extracted as private SRP helper — keeps handler thin, formats intended vs actual with original question context separately
- formatQuestionsForMismatchContext handles missing/malformed toolInput gracefully with fallback string — defensive but non-crashing
- PostToolUse router is a structural mirror of PreToolUse router — enforces consistent extension path for future tool handlers

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Full AskUserQuestion lifecycle complete: PreToolUse (save + wake agent) -> TUI driver (keystrokes + save pending) -> PostToolUse (verify + cleanup)
- Phase 04 is fully complete — all 3 plans done
- settings.json needs PostToolUse event registered for event_post_tool_use.mjs before live use
- Phase 05 can follow the same PostToolUse pattern for any future tool verification needs

---
*Phase: 04-askuserquestion-lifecycle-full-stack*
*Completed: 2026-02-22*
