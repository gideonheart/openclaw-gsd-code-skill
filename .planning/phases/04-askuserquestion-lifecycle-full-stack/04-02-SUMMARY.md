---
phase: 04-askuserquestion-lifecycle-full-stack
plan: 02
subsystem: events
tags: [pre-tool-use, ask-user-question, tui-driver, tmux, gateway, hook-router]

# Dependency graph
requires:
  - phase: 04-01-PLAN
    provides: lib/ask-user-question.mjs (formatQuestionsForAgent, saveQuestionMetadata, readQuestionMetadata, savePendingAnswer)
  - phase: 03-stop-event-full-stack
    provides: readHookContext, wakeAgentWithRetry, appendJsonlEntry, lib/tui-common.mjs sendKeysToTmux/sendSpecialKeyToTmux
provides:
  - events/pre_tool_use/event_pre_tool_use.mjs — PreToolUse hook router dispatching by tool_name
  - events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs — saves question metadata, wakes OpenClaw agent
  - events/pre_tool_use/ask_user_question/prompt_ask_user_question.md — agent decision framework with 6 categories and GSD phase awareness
  - bin/tui-driver-ask.mjs — reads question file, saves pending answer, types all 4 action types into Claude Code TUI
  - sendKeysToTmux and sendSpecialKeyToTmux now exported from lib/tui-common.mjs (previously private)
affects:
  - 04-03-PLAN (PostToolUse handler — verification side of the same AskUserQuestion lifecycle)
  - settings.json registration (PreToolUse hook must point to event_pre_tool_use.mjs)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Router pattern: one file registered per hook event type, dispatches by tool_name — extensible (add folder + if branch per new tool)"
    - "Handler thinness: domain handler ~5-10 lines of logic, all knowledge in lib/ — fire-and-forget wake, then log + return"
    - "TUI driver saves pending answer BEFORE typing keystrokes — PostToolUse can verify even if driver crashes mid-navigation"
    - "Multi-select navigation: sort indices ascending, track current cursor position, calculate delta Down presses per index"

key-files:
  created:
    - events/pre_tool_use/event_pre_tool_use.mjs
    - events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs
    - events/pre_tool_use/ask_user_question/prompt_ask_user_question.md
    - bin/tui-driver-ask.mjs
  modified:
    - lib/tui-common.mjs
    - lib/index.mjs

key-decisions:
  - "sendKeysToTmux and sendSpecialKeyToTmux exported from lib/tui-common.mjs — minimal export surface change, both needed by tui-driver-ask.mjs"
  - "chat action Down count: optionCount + 2 (LOW CONFIDENCE — separator line assumed navigable, needs live testing)"
  - "pendingAnswerAction for multi-question: stores full decisions actions array — PostToolUse handles both single-action string and multi-action array"
  - "Tab key sent between questions in multi-question tabbed forms — per CONTEXT.md tab auto-advance assumption"

patterns-established:
  - "PreToolUse router: readHookContext -> guard null -> read tool_name -> if-dispatch -> else debug log + exit 0"
  - "Domain handler imports: SKILL_ROOT from lib/paths.mjs, domain functions + wakeAgentWithRetry + appendJsonlEntry from lib/index.mjs"
  - "TUI driver structure: shebang, parseArgs, guard clauses, readQuestionMetadata, savePendingAnswer, per-question keystroke loop, appendJsonlEntry, main().catch()"

requirements-completed: [ASK-02, TUI-03, TUI-04]

# Metrics
duration: 3min
completed: 2026-02-22
---

# Phase 04 Plan 02: PreToolUse Handler and AskUserQuestion TUI Driver Summary

**PreToolUse hook router + AskUserQuestion domain handler that saves question metadata, wakes agent, and tui-driver-ask.mjs that navigates Claude Code's question TUI via all 4 keystroke action types**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-22T11:46:19Z
- **Completed:** 2026-02-22T11:49:12Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created PreToolUse hook router (`event_pre_tool_use.mjs`) following exact same structure as `event_stop.mjs` — dispatches by `tool_name`, extensible via folder + if-branch pattern
- Created thin AskUserQuestion domain handler that calls `saveQuestionMetadata` + `formatQuestionsForAgent` + `wakeAgentWithRetry` — 5 logical lines, all domain knowledge in lib
- Created `prompt_ask_user_question.md` with 6-category decision framework (confirmation, style, scope, architecture, open-floor, delegation) and GSD phase awareness table
- Created `bin/tui-driver-ask.mjs` (300 lines) implementing all 4 action types: select (Down x N + Enter), type (navigate to Type something + Enter + text + Enter), multi-select (Space-toggle each sorted index + Enter), chat (navigate to Chat about this + Enter + text + Enter)
- Exported `sendKeysToTmux` and `sendSpecialKeyToTmux` from `lib/tui-common.mjs` (previously unexported private functions) and re-exported from `lib/index.mjs`

## Task Commits

Each task was committed atomically:

1. **Task 1: Create PreToolUse router and AskUserQuestion handler with prompt** - `27ced93` (feat)
2. **Task 2: Create bin/tui-driver-ask.mjs — AskUserQuestion TUI navigator** - `64a3db3` (feat)

**Plan metadata:** (docs commit — see Final Commit below)

## Files Created/Modified
- `events/pre_tool_use/event_pre_tool_use.mjs` — PreToolUse hook router: readHookContext + dispatch by tool_name
- `events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs` — thin domain handler: save metadata + format + wake agent
- `events/pre_tool_use/ask_user_question/prompt_ask_user_question.md` — agent decision framework prompt
- `bin/tui-driver-ask.mjs` — AskUserQuestion TUI driver: all 4 action types, reads question file, saves pending answer
- `lib/tui-common.mjs` — Added `export` keyword to `sendKeysToTmux` and `sendSpecialKeyToTmux`
- `lib/index.mjs` — Updated tui-common re-export to include `sendKeysToTmux` and `sendSpecialKeyToTmux`

## Decisions Made
- `sendKeysToTmux` and `sendSpecialKeyToTmux` exported from `lib/tui-common.mjs` — minimal change (add `export` keyword), necessary for TUI driver SRP separation
- Chat action Down count: `optionCount + 2` (LOW CONFIDENCE — separator line assumed navigable, exact count needs live testing per CONTEXT.md)
- `pendingAnswerAction` for multi-question forms: stores full decisions action array (not just first action) — PostToolUse comparison handles both single string and array
- Tab key sent between questions for multi-question tabbed form navigation

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- PreToolUse handler chain is complete: Claude Code fires AskUserQuestion → handler saves metadata + wakes agent → agent calls tui-driver-ask.mjs → keystrokes submitted
- Ready for Plan 03: PostToolUse verification side (reads pending-answer file, compares with tool_response.answers, wakes agent on mismatch)
- One known LOW CONFIDENCE assumption: "Chat about this" Down count (optionCount + 2) — verify with live Claude Code session before relying on chat action

---
*Phase: 04-askuserquestion-lifecycle-full-stack*
*Completed: 2026-02-22*
