---
phase: quick-20
plan: 20
subsystem: cli
tags: [rotate-session, session-creation, openclaw-cli, execFileSync]

requires: []
provides:
  - "rotate-session.mjs creates new OpenClaw sessions via CLI instead of passively reading sessions.json"
affects: [rotate-session]

tech-stack:
  added: [execFileSync from node:child_process]
  patterns: []

key-files:
  created: []
  modified:
    - bin/rotate-session.mjs

key-decisions:
  - "createNewOpenclawSession uses execFileSync to call openclaw agent CLI — no passive sessions.json read"
  - "Descriptive error thrown if CLI fails OR if sessionId missing from response.result.meta.agentMeta.sessionId"
  - "Removed equality check (newSessionId === oldSessionId) — rotation always creates fresh session, no no-op path"
  - "initialMessage defaults to 'Session rotated' when --label not supplied"

patterns-established: []

requirements-completed: []

duration: 5min
completed: 2026-02-23
---

# Quick Task 20: Fix rotate-session.mjs Summary

**Replaced passive sessions.json read with active `openclaw agent --agent <id> --message <text> --json` CLI call to create new sessions and extract the returned session ID.**

## Performance

- **Duration:** 5 min
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Removed `resolveActiveOpenclawSessionId` function (was reading sessions.json passively — wrong approach)
- Added `createNewOpenclawSession(agentIdentifier, initialMessage)`:
  - Calls `openclaw agent --agent <id> --message <text> --json` via `execFileSync`
  - Parses JSON response
  - Extracts `response.result.meta.agentMeta.sessionId`
  - Throws descriptive errors if CLI call fails or session ID is missing from response
- Removed equality check in `main()` — rotation always creates a fresh session
- Updated file header comment and help text to reflect new active-creation approach
- Added `execFileSync` import from `node:child_process`

## Task Commits

1. **Task 1: Replace passive session read with active session creation** - `a81b043` (feat)

## Files Created/Modified

- `bin/rotate-session.mjs` — Replaced resolveActiveOpenclawSessionId with createNewOpenclawSession, removed equality check, updated header and help text

## Decisions Made

- `createNewOpenclawSession` uses `execFileSync` (synchronous, simple) rather than async — CLI call is fast and the script is already synchronous
- Equality check removed entirely — there is no case where rotation should be a no-op; if called, always create a new session
- `initialMessage` defaults to `'Session rotated'` to match previous label fallback intent

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Self-Check: PASSED

- bin/rotate-session.mjs: FOUND
- .planning/quick/20-fix-rotate-session-mjs-add-force-flag-to/20-SUMMARY.md: FOUND
- Commit a81b043: FOUND
- `--help` output verified: updated usage and description present
- `resolveActiveOpenclawSessionId` removed: confirmed not present in file
- `createNewOpenclawSession` added with error handling: confirmed present
