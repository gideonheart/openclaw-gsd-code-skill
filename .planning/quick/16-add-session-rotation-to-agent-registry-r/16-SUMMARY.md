---
phase: quick-16
plan: 01
subsystem: agent-registry
tags: [session-rotation, registry, cli, atomic-write]
dependency_graph:
  requires: []
  provides: [session-rotation-cli]
  affects: [config/agent-registry.json, config/SCHEMA.md, config/agent-registry.example.json]
tech_stack:
  added: []
  patterns: [atomic-write-tmp-rename, parseArgs-cli, crypto.randomUUID]
key_files:
  created:
    - bin/rotate-session.mjs
  modified:
    - config/agent-registry.example.json
    - config/SCHEMA.md
decisions:
  - "rotate-session.mjs does NOT check agent.enabled — rotating a disabled agent is valid (session IDs are unrelated to enabled state)"
  - "rotated_at only (no created_at) — we do not know when the old session was created; fabricated timestamps would be dishonest"
  - "label key omitted entirely when not provided — no 'label: null' stored in history"
  - "session_file absolute path included — makes old session Ctrl+Click-able in terminals for conversation review"
metrics:
  duration: 1 min
  completed: 2026-02-22
  tasks_completed: 2
  files_created: 1
  files_modified: 2
---

# Quick Task 16: Add Session Rotation to Agent Registry Summary

**One-liner:** CLI script that swaps an agent's `openclaw_session_id` for a fresh UUID and archives the retired ID into a `session_history` array using atomic tmp+rename writes.

## What Was Built

- `bin/rotate-session.mjs` — executable CLI following `launch-session.mjs` patterns exactly: `parseArgs`, `logWithTimestamp`, SRP functions, ESM, SKILL_ROOT via `import.meta.url`
- `config/agent-registry.example.json` — gideon entry now shows a `session_history` array with one example entry; warden entry intentionally omits it (field is optional)
- `config/SCHEMA.md` — `session_history` added to Agent Fields table, new "Session History Entry Fields" section documents all 4 sub-fields

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create bin/rotate-session.mjs CLI script | c064d0c | bin/rotate-session.mjs |
| 2 | Update example config and schema documentation | 6554a0c | config/agent-registry.example.json, config/SCHEMA.md |

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

- bin/rotate-session.mjs exists and is executable: FOUND
- config/agent-registry.example.json contains session_history: FOUND
- config/SCHEMA.md contains Session History Entry Fields section: FOUND
- c064d0c commit exists: FOUND
- 6554a0c commit exists: FOUND
