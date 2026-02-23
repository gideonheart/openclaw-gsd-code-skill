---
phase: quick-24
plan: 01
subsystem: events
tags: [logging, refactor, dry, try-finally, trace]
dependency_graph:
  requires: []
  provides: [single-trace-per-handler-execution]
  affects: [event_stop, event_session_start, event_user_prompt_submit, event_pre_tool_use, event_post_tool_use, handle_ask_user_question, handle_post_ask_user_question]
tech_stack:
  added: []
  patterns: [try-finally-trace, structured-return-from-domain-handlers, decision-path-enum]
key_files:
  created: []
  modified:
    - events/stop/event_stop.mjs
    - events/session_start/event_session_start.mjs
    - events/user_prompt_submit/event_user_prompt_submit.mjs
    - events/pre_tool_use/event_pre_tool_use.mjs
    - events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs
    - events/post_tool_use/event_post_tool_use.mjs
    - events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs
decisions:
  - "try/finally pattern guarantees single trace entry fires on every exit path including early returns"
  - "Domain handlers return { decisionPath, outcome } structs — zero internal logging"
  - "warn level applied for mismatch/no-pending/missing-response paths; info for all others"
metrics:
  duration: 3 min
  completed_date: 2026-02-23
  tasks_completed: 2
  files_modified: 7
---

# Quick Task 24: Consolidate Handler Logs Into Single Trace Entry Per Execution — Summary

## One-liner

Replaced 24 scattered appendJsonlEntry calls across 7 handler files with exactly 5 single-trace entries using try/finally, with domain handlers returning structured `{ decisionPath, outcome }` objects instead of logging internally.

## What Was Built

### Task 1: Standalone handler log consolidation

Three handlers refactored to use the try/finally single-trace pattern:

**event_stop.mjs** — 7 decision paths enumerated: `reentrancy-guard`, `no-message`, `queue-advanced`, `queue-complete`, `awaits-mismatch`, `no-active-command`, `fresh-wake`. Six scattered appendJsonlEntry calls (including the entry-point debug log) replaced with one finally block entry that captures `hook_payload`, `decision_path`, and `outcome`.

**event_session_start.mjs** — 6 decision paths: `clear-awaits-mismatch`, `clear-queue-complete`, `clear-queue-advanced`, `clear-other`, `startup-stale-queue`, `startup-clean`, `unhandled-source`. The `source === 'clear'` block now has explicit handling for all 4 queue action outcomes including the previously implicit `advanced` path and a fallback for unknown actions.

**event_user_prompt_submit.mjs** — 4 decision paths: `tui-driver-input`, `ask-user-question-flow`, `no-queue`, `queue-cancelled`. The `queue-cancelled` outcome now includes `remaining_commands` as an array (was previously joined as a string), making it machine-readable in JSONL.

### Task 2: Router + domain handler refactor

**handle_ask_user_question.mjs** — Removed `appendJsonlEntry` import and single call. Now returns `{ decisionPath: 'ask-user-question', outcome: { tool_use_id, question_count } }`.

**handle_post_ask_user_question.mjs** — Removed all 4 appendJsonlEntry calls. Returns structured results from all 4 exit paths: `ask-user-question-no-pending`, `ask-user-question-missing-response`, `ask-user-question-verified`, `ask-user-question-mismatch`.

**event_pre_tool_use.mjs** — 2 appendJsonlEntry calls replaced with 1 finally block entry. Captures domain handler return value to populate `handlerTrace`. Applies `warn` level for problematic paths.

**event_post_tool_use.mjs** — Same structure as pre_tool_use router. Mirrors the pattern for consistent extensibility.

## Decisions Made

- **try/finally trace pattern** — guarantees trace fires on every exit path including early guard returns, without needing to duplicate appendJsonlEntry at each exit point.
- **Domain handlers return structs, not void** — `{ decisionPath, outcome }` return value makes domain logic testable and removes coupling to the logging infrastructure.
- **warn level for problematic paths** — `ask-user-question-mismatch`, `ask-user-question-no-pending`, `ask-user-question-missing-response` use `warn`; all others use `info`. This makes filtering JSONL logs trivial.
- **No `extracted` field** — the full `hook_payload` in the trace entry already contains all raw data; a separate extracted block would duplicate it.
- **Pre-hookContext guard stays outside try** — `if (!hookContext) process.exit(0)` fires before `sessionName` is available, so there is nothing to trace.

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

All 7 files pass `node -c` syntax check. appendJsonlEntry call distribution:

| File | Calls |
|------|-------|
| events/stop/event_stop.mjs | 1 (finally block) |
| events/session_start/event_session_start.mjs | 1 (finally block) |
| events/user_prompt_submit/event_user_prompt_submit.mjs | 1 (finally block) |
| events/pre_tool_use/event_pre_tool_use.mjs | 1 (finally block) |
| events/post_tool_use/event_post_tool_use.mjs | 1 (finally block) |
| events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs | 0 |
| events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs | 0 |

Total: 5 calls (was 24). lib/logger.mjs not modified.

## Commits

| Task | Hash | Message |
|------|------|---------|
| Task 1 | a568dcb | refactor(quick-24): consolidate standalone handler logs into single trace per execution |
| Task 2 | f0cc258 | refactor(quick-24): consolidate router+domain handler logs with return value refactor |

## Self-Check: PASSED

All 7 modified files verified present on disk. Both commits (a568dcb, f0cc258) verified in git log.
