---
phase: 04-askuserquestion-lifecycle-full-stack
plan: 01
subsystem: lib
tags: [ask-user-question, domain-module, file-io, atomic-writes, answer-verification]

# Dependency graph
requires:
  - phase: 03-stop-event-full-stack
    provides: queue-processor.mjs atomic write pattern, QUEUES_DIRECTORY constant pattern
  - phase: 02-shared-library
    provides: lib/logger.mjs appendJsonlEntry, lib/paths.mjs SKILL_ROOT
provides:
  - lib/ask-user-question.mjs with 8 exported domain functions for AskUserQuestion lifecycle
  - formatQuestionsForAgent — produces gateway message format for OpenClaw agent
  - saveQuestionMetadata / readQuestionMetadata / deleteQuestionMetadata — question file I/O
  - savePendingAnswer / readPendingAnswer / deletePendingAnswer — pending answer file I/O
  - compareAnswerWithIntent — answer verification across 4 action types (select, type, multi-select, chat)
affects:
  - 04-02-PLAN (PreToolUse handler imports saveQuestionMetadata, formatQuestionsForAgent)
  - 04-03-PLAN (PostToolUse handler imports readPendingAnswer, compareAnswerWithIntent, deleteQuestionMetadata, deletePendingAnswer)
  - bin/tui-driver-ask.mjs (reads question metadata, saves pending answer)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Internal helper functions (resolveQuestionFilePath, resolvePendingAnswerFilePath, writeFileAtomically) are unexported module-private functions — only domain functions are exported"
    - "Answer key format flexibility: toolResponse.answers keys may be string indices or question text — resolveAnswerValueForQuestion tries index first, falls back to question text"
    - "chat action always returns matched:true — breaks normal TUI flow, next event handles outcome"
    - "Atomic tmp+rename for all file writes (same pattern as queue-processor.mjs writeQueueFileAtomically)"

key-files:
  created:
    - lib/ask-user-question.mjs
  modified:
    - lib/index.mjs

key-decisions:
  - "compareAnswerWithIntent takes (pendingAnswer, toolResponse, toolInput) — pendingAnswer.answers stores intent by question index (not by label), toolResponse.answers uses question-text or index keys"
  - "Select action intent stored as optionIndex (number), not label — label resolved at comparison time from toolInput.questions[i].options[j].label"
  - "resolveAnswerValueForQuestion: string-index key tried first (matches RESEARCH.md open question 1 format detection with debug logging)"
  - "chat action skips verification entirely — per CONTEXT.md: breaks normal answer flow, next event handles outcome"
  - "tool_use_id mismatch: log warning but proceed — per RESEARCH.md Pitfall 4, don't block on stale correlation IDs"

patterns-established:
  - "Internal file path helpers (resolveXxxFilePath) follow queue-processor.mjs naming: resolve(QUEUES_DIRECTORY, prefix + sessionName + .json)"
  - "File delete functions: unlinkSync wrapped in try/catch, ENOENT silently ignored, other errors rethrown"
  - "File read functions: readFileSync + JSON.parse in try/catch, ENOENT returns null, other errors rethrown"

requirements-completed: [ASK-01, ASK-03]

# Metrics
duration: 2min
completed: 2026-02-22
---

# Phase 04 Plan 01: AskUserQuestion Domain Module Summary

**Shared AskUserQuestion domain library with 8 functions: question/pending-answer atomic file I/O, gateway message formatting, and 4-action-type answer verification comparison**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-22T11:40:18Z
- **Completed:** 2026-02-22T11:43:07Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created `lib/ask-user-question.mjs` as the single source of truth for all AskUserQuestion domain knowledge — all Phase 4 handlers and the TUI driver import from here
- `formatQuestionsForAgent` produces the exact CONTEXT.md gateway message format: question headers with single/multi-select flags, numbered option list with descriptions, How to answer block, CLI call instruction with absolute SKILL_ROOT path
- `compareAnswerWithIntent` handles all 4 action types: select (label lookup + case-insensitive match), type (substring match for typed text), multi-select (all selected labels present in response), chat (always matched — skip verification)
- Answer key format flexibility built in: `resolveAnswerValueForQuestion` tries string index first, falls back to question text matching (handles real PostToolUse payload format variation)
- All file I/O uses atomic tmp+rename pattern (same as queue-processor.mjs) with ENOENT-safe reads and deletes
- Updated `lib/index.mjs` to re-export all 8 functions as first export line (alphabetical order)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lib/ask-user-question.mjs** - `e8afd3d` (feat)
2. **Task 2: Update lib/index.mjs re-exports** - `4f36c79` (feat)

**Plan metadata:** (docs commit — see Final Commit below)

## Files Created/Modified
- `lib/ask-user-question.mjs` — AskUserQuestion domain module: 8 exported functions, 4 internal helpers, JSDoc on all exports
- `lib/index.mjs` — Added ask-user-question.mjs re-export line as first entry (alphabetical)

## Decisions Made
- `compareAnswerWithIntent` parameter order: `(pendingAnswer, toolResponse, toolInput)` — matches caller pattern in PostToolUse handler
- Select intent stored as `optionIndex` number, label resolved at comparison time — avoids label duplication in pending-answer file
- `chat` action always returns `matched: true` — per CONTEXT.md decision: chat breaks normal flow, next event handles outcome, no special queue logic needed
- `tool_use_id` mismatch logs a warning but proceeds — per RESEARCH.md Pitfall 4
- `resolveAnswerValueForQuestion` logs key format detected at debug level — addresses RESEARCH.md Open Question 1 (index vs text key format) with live telemetry

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- `lib/ask-user-question.mjs` is ready for import by Phase 4 handler plans (04-02, 04-03) and `bin/tui-driver-ask.mjs`
- `lib/index.mjs` re-exports all 8 functions — event handlers can import from single path
- No blockers for Phase 4 Plan 02

## Self-Check: PASSED

- lib/ask-user-question.mjs: FOUND
- lib/index.mjs: FOUND
- 04-01-SUMMARY.md: FOUND
- Commit e8afd3d (Task 1): FOUND
- Commit 4f36c79 (Task 2): FOUND

---
*Phase: 04-askuserquestion-lifecycle-full-stack*
*Completed: 2026-02-22*
