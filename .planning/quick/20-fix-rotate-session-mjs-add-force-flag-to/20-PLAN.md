---
phase: quick-20
title: "Fix rotate-session.mjs: create new session via OpenClaw gateway instead of passive read"
autonomous: true
---

# Quick Task 20 — Fix rotate-session.mjs

## Goal

The script currently reads `sessions.json` to find the "most recent" session and compares it to the stored one — this is wrong. The purpose of rotation is to **create a new OpenClaw session** when context is full, then update `config/agent-registry.json` with the new session ID.

## Plan 01: Rewrite rotation logic to create sessions via gateway

### Task 1: Replace passive session read with active session creation

**files:** `bin/rotate-session.mjs`
**action:**

1. Add `import { execFileSync } from 'node:child_process'`
2. Remove `resolveActiveOpenclawSessionId` function entirely (passive sessions.json read — wrong approach)
3. Add new function `createNewOpenclawSession(agentIdentifier, initialMessage)` that:
   - Calls `openclaw agent --agent <agentIdentifier> --message <initialMessage> --json`
   - Parses JSON response
   - Extracts session ID from `response.result.meta.agentMeta.sessionId`
   - Returns the new session ID
   - Throws descriptive error if call fails or session ID missing from response
4. Update `main()`:
   - Remove the equality check (`newSessionId === oldSessionId` block) — we always create a fresh session
   - Replace `resolveActiveOpenclawSessionId(agentIdentifier)` call with `createNewOpenclawSession(agentIdentifier, label || 'Session rotated')`
   - Keep: archive old session in history, write new ID to registry (existing logic is fine)
5. Update file header comment to reflect new behavior
6. Update help text (no `--force` flag needed)

**verify:** `node bin/rotate-session.mjs --help` shows updated usage
**done:** Script creates a new OpenClaw session via gateway and updates agent-registry.json

### Key constraints
- Keep `OPENCLAW_AGENTS_BASE_PATH` — still needed by `buildSessionHistoryEntry` for session file path
- Keep atomic registry writes (`writeRegistryAtomically`)
- Keep all existing helper functions that are still used
- Self-explanatory names, no abbreviations (CLAUDE.md rule)
- DRY + SRP
