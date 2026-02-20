---
phase: quick-10
plan: 1
subsystem: lib/gateway + event-handlers
tags: [dry, refactor, gateway, retry, handlers]
dependency_graph:
  requires: []
  provides: [wakeAgentWithRetry in lib/gateway.mjs]
  affects: [events/stop, events/session_start, events/user_prompt_submit]
tech_stack:
  added: []
  patterns: [compose-helper pattern — convenience wrapper over raw function + retry]
key_files:
  created: []
  modified:
    - lib/gateway.mjs
    - lib/index.mjs
    - events/stop/event_stop.mjs
    - events/session_start/event_session_start.mjs
    - events/user_prompt_submit/event_user_prompt_submit.mjs
decisions:
  - wakeAgentWithRetry lives in gateway.mjs alongside wakeAgentViaGateway — related by concern, single import for callers
  - operationLabel uses eventType.toLowerCase() for unique per-event log labels rather than a fixed string
  - eventMetadata timestamp built at call time inside helper — each retry gets a fresh timestamp
metrics:
  duration_seconds: 121
  completed_date: "2026-02-20"
  tasks_completed: 2
  files_modified: 5
---

# Quick Task 10: Extract wakeAgentWithRetry Helper — DRY Refactor Summary

**One-liner:** Extracted `wakeAgentWithRetry` helper into `lib/gateway.mjs` composing `wakeAgentViaGateway` + `retryWithBackoff`, replacing 60 lines of duplicated boilerplate across 3 handlers with 5 one-line calls.

## What Was Done

### Task 1 — Add wakeAgentWithRetry to gateway.mjs and re-export from index.mjs

Added `wakeAgentWithRetry()` to `lib/gateway.mjs` immediately after `wakeAgentViaGateway()`. The helper:

- Accepts `{ resolvedAgent, messageContent, promptFilePath, eventType, sessionName }` — all the caller-side context
- Builds `eventMetadata` internally (`{ eventType, sessionName, timestamp: new Date().toISOString() }`)
- Delegates to `retryWithBackoff(() => wakeAgentViaGateway(...), { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: wake-on-${eventType.toLowerCase()}, sessionName })`
- Returns the Promise from `retryWithBackoff` directly (no `async/await` overhead needed)

Updated the module header comment to document both exports. Added `import { retryWithBackoff } from './retry.mjs'`.

Updated `lib/index.mjs` re-export line from `wakeAgentViaGateway` to `wakeAgentViaGateway, wakeAgentWithRetry`.

Commit: `6edc631`

### Task 2 — Replace all 5 call sites with wakeAgentWithRetry

**event_stop.mjs** (2 call sites):
- Queue-complete path: 12-line block → 1 line
- Fresh-wake path: 12-line block → 1 line
- Removed `retryWithBackoff` and `wakeAgentViaGateway` from imports
- Updated stale doc comment that still referenced `wakeAgentViaGateway`

**event_session_start.mjs** (2 call sites):
- Queue-complete on clear: 12-line block → 1 line
- Stale archive startup: 12-line block → 1 line
- Removed `retryWithBackoff` and `wakeAgentViaGateway` from imports

**event_user_prompt_submit.mjs** (1 call site):
- Queue cancel: 12-line block → 1 line
- Removed `retryWithBackoff` and `wakeAgentViaGateway` from imports

Commit: `7de9f06`

## Verification Results

| Check | Expected | Result |
|-------|----------|--------|
| `node --check lib/gateway.mjs` | pass | PASS |
| `node --check events/stop/event_stop.mjs` | pass | PASS |
| `node --check events/session_start/event_session_start.mjs` | pass | PASS |
| `node --check events/user_prompt_submit/event_user_prompt_submit.mjs` | pass | PASS |
| `retryWithBackoff` in events/ | 0 matches | 0 |
| `wakeAgentViaGateway` in events/ | 0 matches | 0 |
| `await wakeAgentWithRetry` in events/ | 5 matches | 5 |

## Deviations from Plan

None - plan executed exactly as written.

One minor addition beyond the plan: updated a stale doc comment in `event_stop.mjs` that still referenced `wakeAgentViaGateway` in prose (line 13). Updated to `wakeAgentWithRetry` to match the new reality. This is a Rule 1 (accuracy) fix, not a structural deviation.

## Self-Check: PASSED

All 5 modified files present on disk. Both commits (6edc631, 7de9f06) confirmed in git history.
