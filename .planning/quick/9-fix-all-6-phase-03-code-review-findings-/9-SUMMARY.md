---
phase: quick-9
plan: 1
subsystem: hook-handlers
tags: [refactor, dry, reliability, api-cleanup, debug-logging]
dependency_graph:
  requires: [lib/agent-resolver.mjs, lib/logger.mjs, lib/retry.mjs, lib/gateway.mjs, lib/paths.mjs, lib/queue-processor.mjs]
  provides: [lib/hook-context.mjs]
  affects: [events/stop/event_stop.mjs, events/session_start/event_session_start.mjs, events/user_prompt_submit/event_user_prompt_submit.mjs, bin/tui-driver.mjs]
tech_stack:
  added: []
  patterns: [shared-context-reader, retryWithBackoff-wrapper, SKILL_ROOT-path-resolution, guard-clause-debug-logging]
key_files:
  created:
    - lib/hook-context.mjs
  modified:
    - lib/index.mjs
    - lib/tui-common.mjs
    - lib/queue-processor.mjs
    - events/stop/event_stop.mjs
    - events/session_start/event_session_start.mjs
    - events/user_prompt_submit/event_user_prompt_submit.mjs
    - bin/tui-driver.mjs
decisions:
  - readHookContext returns null on any guard failure — caller does single null check and exits 0
  - readHookContext imports directly from agent-resolver.mjs and logger.mjs (not index.mjs) to avoid circular dependency
  - sendKeysToTmux trailing '' hardcoded internally with comment explaining tmux 3.x behavior
  - promptFilePath in session_start and user_prompt_submit uses SKILL_ROOT+events+stop path (not relative navigation)
  - queue overwrite warning is non-blocking — overwrite proceeds, warn makes event visible in logs
metrics:
  duration: 2 min
  completed_date: 2026-02-20
  tasks_completed: 3
  files_modified: 7
  files_created: 1
---

# Quick Task 9: Fix All 6 Phase 03 Code Review Findings Summary

**One-liner:** Extracted handler boilerplate into `readHookContext`, added debug logging on all guard exits, wrapped all `wakeAgentViaGateway` calls in `retryWithBackoff`, cleaned `sendKeysToTmux` API, fixed `promptFilePath` path coupling, and added queue overwrite warning.

## Objective

Fix all 6 Phase 03 code review findings from REVIEW.md Section 8 priorities to eliminate DRY violations, improve operability (debug logging), add reliability (retry), clean APIs, and reduce fragile coupling before Phase 04 adds more handlers.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create readHookContext helper, fix sendKeysToTmux API, add queue-processor comment | 2acf71a | lib/hook-context.mjs (new), lib/index.mjs, lib/tui-common.mjs, lib/queue-processor.mjs |
| 2 | Refactor all 3 handlers — readHookContext, debug logging, retryWithBackoff, SKILL_ROOT paths | a905bbc | events/stop/event_stop.mjs, events/session_start/event_session_start.mjs, events/user_prompt_submit/event_user_prompt_submit.mjs |
| 3 | Add queue-overwrite warning in tui-driver.mjs | 8c26008 | bin/tui-driver.mjs |

## Findings Fixed

### Finding 3.1 — DRY violation: handler boilerplate repeated 3 times
**Resolution:** Created `lib/hook-context.mjs` with `readHookContext(handlerSource)` that extracts the 15-line stdin/JSON/session/agent block. All 3 handlers replaced with a single call returning `{ hookPayload, sessionName, resolvedAgent }` or `null`.

### Finding 3.2 — No debug logging on guard exits
**Resolution:** `readHookContext` logs a `debug`-level JSONL entry for each guard failure (invalid JSON, no session name, unmanaged session). Each handler also logs `debug` entries on its own handler-specific guard exits (re-entrancy, no message, awaits-mismatch, no-active-command, no queue to cancel).

### Finding 3.3 — promptFilePath uses fragile relative navigation (`../stop/`)
**Resolution:** `event_session_start.mjs` and `event_user_prompt_submit.mjs` now import `SKILL_ROOT` from `../../lib/paths.mjs` and resolve via `resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md')`. `event_stop.mjs` correctly resolves relative to its own directory (already correct).

### Finding 3.4 — In-place mutation of parsed JSON without explanatory comment
**Resolution:** Added 3-line inline comment before `activeCommand.status = 'done'` in `queue-processor.mjs` explaining that in-place mutation is safe because Claude Code fires events sequentially per session.

### Finding 3.5 — `sendKeysToTmux` exposes `keyLiteralFlag` as public parameter
**Resolution:** Removed `keyLiteralFlag` parameter. Function now has signature `sendKeysToTmux(tmuxSessionName, textToType)`. The `''` is hardcoded internally with a comment explaining the observed tmux 3.x behavior. All internal call sites updated (3 removed trailing `''` arguments).

### Finding 3.6 — `tui-driver.mjs` silently overwrites existing queue files
**Resolution:** Added `existsSync` check before `writeQueueFileAtomically`. If a queue file already exists, a `warn`-level JSONL entry is logged (`'Overwriting existing queue — previous queue may have been incomplete'`). The overwrite still proceeds by design — the warning makes the event visible for diagnostics.

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

All 10 verification checks passed:
1. `node --check lib/hook-context.mjs` — PASS
2. `node --check lib/tui-common.mjs` — PASS
3. `node --check events/stop/event_stop.mjs` — PASS
4. `node --check events/session_start/event_session_start.mjs` — PASS
5. `node --check events/user_prompt_submit/event_user_prompt_submit.mjs` — PASS
6. `node --check bin/tui-driver.mjs` — PASS
7. `grep readFileSync.*stdin events/` — zero matches (PASS)
8. `grep keyLiteralFlag lib/` — zero matches (PASS)
9. `grep \.\./stop/ events/` — zero matches (PASS)
10. `grep retryWithBackoff events/` — 8 matches across 3 files (PASS)

## Self-Check: PASSED

All created/modified files verified present on disk. All 3 task commits verified in git log (2acf71a, a905bbc, 8c26008).
