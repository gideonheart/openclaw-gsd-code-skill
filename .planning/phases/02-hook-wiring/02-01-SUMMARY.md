---
phase: 02-hook-wiring
plan: 01
subsystem: hook-registration
tags: [hooks, configuration, settings.json, idempotent, event-driven]
requires: [CONFIG-03]
provides: [CONFIG-03]
affects: [hook-system, session-lifecycle]
tech_stack:
  added: []
  patterns: [idempotent-registration, atomic-updates, jq-merge]
key_files:
  created:
    - scripts/register-hooks.sh
  modified:
    - ~/.claude/settings.json
decisions:
  - "PreCompact with no matcher (fires on both auto and manual) for full visibility"
  - "Stop/Notification/PreCompact timeout: 600s, SessionEnd uses default"
  - "Registration script in scripts/ (executable utility, not static config)"
metrics:
  duration_minutes: 1
  completed_date: 2026-02-17
  task_count: 2
  file_count: 1
  commits: 1
---

# Phase 02 Plan 01: Hook Registration Script Summary

**One-liner:** Idempotent hook registration script wiring all 5 hook events (Stop, Notification idle/permission, SessionEnd, PreCompact) into Claude Code's native hook system via ~/.claude/settings.json.

## What Was Built

Created production-ready hook registration infrastructure that transforms Claude Code sessions from polling-based to event-driven orchestration:

1. **scripts/register-hooks.sh** - Idempotent registration utility (240 lines):
   - Standard bash header with `set -euo pipefail` and timestamp logging
   - SKILL_ROOT resolution from script location for absolute path construction
   - Pre-flight checks: jq installed, settings.json exists, all 5 hook scripts exist
   - Timestamped backup before modification (settings.json.backup-{epoch})
   - Complete hooks configuration built as JSON with absolute paths from SKILL_ROOT
   - jq merge operation with --argjson preserving non-hook settings
   - SessionStart cleanup: removes gsd-session-hook.sh while preserving gsd-check-update.js
   - JSON validation before atomic file replacement (tmp file + mv)
   - Verification output showing all registered hooks and SessionStart cleanup
   - Clear messaging about session restart requirement

2. **Hook Registration** in ~/.claude/settings.json:
   - **Stop**: No matcher, timeout 600s, calls stop-hook.sh
   - **Notification (idle_prompt)**: Matcher "idle_prompt", timeout 600s, calls notification-idle-hook.sh
   - **Notification (permission_prompt)**: Matcher "permission_prompt", timeout 600s, calls notification-permission-hook.sh
   - **SessionEnd**: No matcher, default timeout, calls session-end-hook.sh (fires on ALL exit reasons per user constraint)
   - **PreCompact**: No matcher, timeout 600s, calls pre-compact-hook.sh (fires on both auto and manual per discretion decision)

3. **SessionStart Cleanup**: gsd-session-hook.sh removed from hooks array, gsd-check-update.js preserved

## Requirements Fulfilled

| Requirement | Status | Evidence |
|-------------|--------|----------|
| CONFIG-03 | ✓ | All 5 hooks registered in settings.json, gsd-session-hook.sh removed from SessionStart |

## Must-Haves Verification

**Truths:**
- ✓ Stop hook registered in ~/.claude/settings.json calling stop-hook.sh
- ✓ Notification hook registered with matcher 'idle_prompt' calling notification-idle-hook.sh
- ✓ Notification hook registered with matcher 'permission_prompt' calling notification-permission-hook.sh
- ✓ SessionEnd hook registered with no matcher calling session-end-hook.sh
- ✓ PreCompact hook registered with no matcher calling pre-compact-hook.sh
- ✓ gsd-session-hook.sh removed from SessionStart hooks array
- ✓ gsd-check-update.js preserved in SessionStart hooks array
- ✓ Registration script is idempotent (safe to run multiple times with same result)

**Artifacts:**
- ✓ scripts/register-hooks.sh (240 lines, min 60 required)

**Key Links:**
- ✓ scripts/register-hooks.sh → ~/.claude/settings.json (jq merge with atomic file replacement)
- ✓ scripts/register-hooks.sh → scripts/stop-hook.sh (absolute path in hook command field)
- ✓ scripts/register-hooks.sh → scripts/notification-idle-hook.sh (absolute path in hook command field)
- ✓ scripts/register-hooks.sh → scripts/notification-permission-hook.sh (absolute path in hook command field)
- ✓ scripts/register-hooks.sh → scripts/session-end-hook.sh (absolute path in hook command field)
- ✓ scripts/register-hooks.sh → scripts/pre-compact-hook.sh (absolute path in hook command field)

## Deviations from Plan

None - plan executed exactly as written. All tasks completed without requiring auto-fixes, blocking issues, or architectural decisions.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 173e3a8 | feat | Create idempotent hook registration script |

## Technical Notes

**jq Merge Pattern:**
The registration script uses a three-stage jq operation:
1. Ensure `.hooks` object exists with `// {}` fallback
2. Replace target hook events (Stop, Notification, SessionEnd, PreCompact) with new configuration
3. Clean SessionStart conditionally: if SessionStart exists, filter out gsd-session-hook.sh while keeping other hooks; if not, create empty array

This approach is idempotent - running multiple times produces identical results without duplicating entries.

**Absolute Path Construction:**
All hook commands use absolute paths constructed from `SKILL_ROOT=$(cd "$(dirname "$0")/.." && pwd)`, which resolves to the gsd-code-skill directory regardless of where the script is executed from.

**Atomic File Updates:**
The script writes to `settings.json.tmp`, validates with `jq empty`, then moves to `settings.json` in a single atomic operation. If validation fails, tmp file is removed and settings.json remains unchanged.

**Pre-flight Checks:**
Script validates all prerequisites before making changes:
- jq is installed and available in PATH
- settings.json exists (creates minimal `{}` if missing with warning)
- All 5 hook scripts exist at expected paths in scripts/ directory

**Verification Output:**
After registration, the script queries settings.json to confirm:
- Each of the 5 hook events is registered with correct command path
- SessionStart hooks array does NOT contain gsd-session-hook.sh
- SessionStart hooks array DOES contain gsd-check-update.js

**SessionEnd Matcher Decision:**
Per user constraint, SessionEnd has NO matcher - fires on ALL exit reasons (logout, /clear, prompt_input_exit, other). The OpenClaw agent receives the `reason` field in stdin JSON and decides relevance.

**PreCompact Matcher Decision:**
Per discretion decision, PreCompact has NO matcher - fires on both `auto` (context window full) and `manual` (/compact command). The agent receives the `trigger` field in stdin JSON and can filter if needed. No cost to extra visibility.

**Timeout Values:**
- Stop, Notification, PreCompact: 600s (10 minutes) - allows for network latency + agent processing in bidirectional mode
- SessionEnd: Default timeout (not specified) - sufficient for fire-and-forget notification

**Backup Strategy:**
Script creates timestamped backup before each run (settings.json.backup-{epoch}). This enables rollback if needed and prevents accidental overwrites during testing.

**Idempotency Verification:**
Verified by running script twice and comparing `.hooks` structure before and after second run - identical output confirms idempotency.

## Verification Results

All 9 verification checks passed:

1. Stop hook registered: `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh` ✓
2. Notification hooks registered with correct matchers:
   - idle_prompt → notification-idle-hook.sh ✓
   - permission_prompt → notification-permission-hook.sh ✓
3. SessionEnd hook registered: `session-end-hook.sh` ✓
4. PreCompact hook registered: `pre-compact-hook.sh` ✓
5. gsd-session-hook.sh removed from SessionStart: `[]` (empty array) ✓
6. gsd-check-update.js preserved in SessionStart: present ✓
7. Valid JSON: `jq empty` passed ✓
8. Non-hook settings preserved: hooks, statusLine, enabledPlugins, skipDangerousModePermissionPrompt ✓
9. Idempotency confirmed: second run produced identical hooks structure ✓

## Next Steps

Phase 02 is now complete - all hook scripts from Phase 01 are wired into Claude Code's native hook system. New Claude Code sessions will fire Stop, Notification, SessionEnd, and PreCompact hooks instead of relying on the obsolete SessionStart-based hook-watcher polling system.

Phase 03 will implement registry-based system prompt injection and agent identity system.

## Self-Check

Verifying all claimed files and commits exist.

**Files created:**
- scripts/register-hooks.sh: FOUND (240 lines, executable)

**Files modified:**
- ~/.claude/settings.json: FOUND (all 5 hooks registered, gsd-session-hook.sh removed, gsd-check-update.js preserved)

**Commits:**
- 173e3a8: FOUND

**Verification checks:**
- Script passes bash -n syntax check: PASSED
- Script is executable: PASSED (chmod +x)
- All 5 hook script paths referenced: PASSED (10 occurrences)
- gsd-session-hook.sh removal logic exists: PASSED (8 occurrences)
- Stop hook registered in settings.json: PASSED
- Notification hooks registered with matchers: PASSED
- SessionEnd hook registered: PASSED
- PreCompact hook registered: PASSED
- gsd-session-hook.sh removed from SessionStart: PASSED
- gsd-check-update.js preserved in SessionStart: PASSED
- Valid JSON: PASSED
- Non-hook settings preserved: PASSED
- Idempotency confirmed: PASSED

## Self-Check: PASSED

All files exist, all commits verified, all must-haves satisfied, all verification checks passed.
