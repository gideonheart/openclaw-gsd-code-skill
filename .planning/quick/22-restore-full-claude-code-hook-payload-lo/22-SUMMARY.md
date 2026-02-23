---
phase: quick-22
plan: 22
subsystem: hook-installer
tags: [hooks, install-hooks, logger, settings]
dependency_graph:
  requires: []
  provides: [hook-logger-default-on, no-logger-flag]
  affects: [bin/install-hooks.mjs, ~/.claude/settings.json]
tech_stack:
  added: []
  patterns: [flag-inversion, dual-variable-semantics]
key_files:
  modified:
    - bin/install-hooks.mjs
  created: []
decisions:
  - "Two separate flag variables (noLoggerOnInstall vs includeLogger) to avoid semantic confusion between install and remove modes"
  - "Remove-mode --logger semantics unchanged: --remove --logger still removes logger entries"
metrics:
  duration: "1 min"
  completed_date: "2026-02-23"
  tasks_completed: 2
  files_modified: 1
---

# Quick Task 22: Restore Full Claude Code Hook Payload Logging Summary

**One-liner:** Inverted install-hooks.mjs default so logger installs by default with --no-logger opt-out, and restored all 14 hook events + logger in settings.json.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Flip install-hooks.mjs default — logger ON, add --no-logger flag | 2449649 | bin/install-hooks.mjs |
| 2 | Run installer to restore settings.json with all hooks | (runtime) | ~/.claude/settings.json |

## What Was Done

### Task 1: Flip install-hooks.mjs default

Changed three things in `bin/install-hooks.mjs`:

1. Added `const noLoggerOnInstall = process.argv.includes('--no-logger');` (new variable)
2. Inverted the `keepFilter` logic: default is now `() => true` (include everything), `--no-logger` activates `isHandlerEntry` filter
3. Inverted `modeLabel`: default is `'handlers + logger'`, `--no-logger` gives `'handlers only'`
4. Updated JSDoc usage comment to reflect the new interface
5. Kept `includeLogger` variable intact — it is only used in remove mode (`--remove --logger`) and has different semantics (target for removal, not install inclusion)

### Task 2: Restored settings.json

Ran `node bin/install-hooks.mjs` (no flags). Result:

- 14 hook events installed (all event types in config/hooks.json)
- 18 logger entries (Notification has 5 matchers = 5 entries)
- 5 handler entries (SessionStart, UserPromptSubmit, PreToolUse[AskUserQuestion], PostToolUse[AskUserQuestion], Stop)
- Non-hook settings preserved: statusLine, enabledPlugins, skipDangerousModePermissionPrompt

## Verification Results

```
node bin/install-hooks.mjs --dry-run
[dry-run] Mode: handlers + logger
[dry-run] Would install 14 hook events (5 handlers, 18 loggers)

node bin/install-hooks.mjs --no-logger --dry-run
[dry-run] Mode: handlers only
[dry-run] Would install 5 hook events (5 handlers, 0 loggers)
```

All 14 hook event types confirmed with logger active after install.

## Deviations from Plan

### Note: Event count discrepancy

The plan states "15 hook events" but config/hooks.json has 14 event type keys (Notification is one key with 5 sub-matcher entries). The automated verification check used `>= 15` which would fail. This is a count error in the plan — the actual behavior (logger on every event type) is correct and verified. All 14 event types have logger active.

No code changes were needed beyond what the plan specified.

## Self-Check: PASSED

- bin/install-hooks.mjs modified: FOUND
- Commit 2449649 exists: FOUND
- settings.json has logger in all 14 event types: VERIFIED
- Non-hook settings preserved: VERIFIED
