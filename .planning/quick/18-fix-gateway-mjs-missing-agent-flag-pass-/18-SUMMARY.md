---
phase: quick-18
plan: 01
subsystem: gateway
tags: [openclaw, cli, agent-routing, session-id]

requires:
  - phase: quick-16
    provides: agent registry with agent_id field on agent objects

provides:
  - wakeAgentViaGateway with required agentId parameter threaded into --agent CLI flag
  - Both JSONL log entries (success and error) include agent_id field

affects: [all event handlers that call wakeAgentWithRetry]

tech-stack:
  added: []
  patterns: [agentId required guard before openclawSessionId guard — fail early on routing identity]

key-files:
  created: []
  modified:
    - lib/gateway.mjs

key-decisions:
  - "agentId added as required parameter to wakeAgentViaGateway — throws if missing, same guard pattern as openclawSessionId"
  - "resolvedAgent.agent_id extracted in wakeAgentWithRetry and passed as agentId — zero caller changes in events/"

requirements-completed: []

duration: 1min
completed: 2026-02-22
---

# Quick Task 18: Fix gateway.mjs Missing --agent Flag Summary

**openclaw CLI now receives `--agent {id} --session-id {uuid}` so rotated sessions route to the correct agent instead of landing under 'main'**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-22T22:17:00Z
- **Completed:** 2026-02-22T22:18:04Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Added `agentId` as a required parameter to `wakeAgentViaGateway` with an early-return guard that throws a descriptive error if missing
- Inserted `'--agent', agentId` into the `openclawArguments` array immediately after `'agent'` and before `'--session-id'`
- Added `agent_id: agentId` to both JSONL log entries (success and error paths)
- Extracted `resolvedAgent.agent_id` in `wakeAgentWithRetry` and threaded it through — zero changes to any caller in `events/`
- Updated module-level doc comment and JSDoc `@param` block to reflect the new `--agent --session-id` pattern

## Task Commits

1. **Task 1: Add agentId parameter to wakeAgentViaGateway and thread through wakeAgentWithRetry** - `6d60b60` (fix)

## Files Created/Modified

- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/lib/gateway.mjs` - Added agentId parameter, --agent CLI flag, agent_id in JSONL logs

## Decisions Made

- agentId required guard placed before openclawSessionId guard — routing identity (who) should fail before session identity (which session)
- No changes to any event handler — resolvedAgent already carries agent_id from the registry; wakeAgentWithRetry is the sole extraction point

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Gateway now passes --agent flag on every wake delivery
- All 7 call sites in events/ continue to work unchanged (they pass resolvedAgent which has agent_id)
- Phase 05 can proceed without any gateway concerns

## Self-Check: PASSED

- lib/gateway.mjs: FOUND
- 18-SUMMARY.md: FOUND
- commit 6d60b60: FOUND

---
*Phase: quick-18*
*Completed: 2026-02-22*
