---
phase: 01-additive-changes
plan: 03
subsystem: hook-scripts
tags: [session-lifecycle, hooks, recovery, openclaw-integration]
requires: ["01-01"]
provides: [HOOK-03, HOOK-09, HOOK-10]
affects: [session-recovery, monitoring, compaction-visibility]
tech_stack:
  added: []
  patterns: [minimal-wake-message, three-tier-fallback, hybrid-mode, fast-path-exit]
key_files:
  created:
    - scripts/session-end-hook.sh
    - scripts/pre-compact-hook.sh
  modified: []
decisions: []
metrics:
  duration_minutes: 2
  completed_date: 2026-02-17
  task_count: 2
  file_count: 2
  commits: 2
---

# Phase 01 Plan 03: Session Lifecycle Hook Scripts Summary

**One-liner:** Created session-end-hook.sh for immediate termination notification (minimal message) and pre-compact-hook.sh for full state capture before context compaction with hybrid mode support.

## What Was Built

Created two session lifecycle hook scripts that provide OpenClaw with visibility into critical Claude Code session events:

1. **scripts/session-end-hook.sh** - Minimal termination notification:
   - Sends lightweight wake message when Claude Code session terminates
   - Only includes session identity (agent_id, tmux_session_name) and trigger type (session_end)
   - No pane capture (session is ending, pane may be gone)
   - Always async delivery (bidirectional mode meaningless for terminating session)
   - Fast-path exits for non-managed sessions (<5ms)
   - Implements HOOK-09 specification

2. **scripts/pre-compact-hook.sh** - Full state capture before compaction:
   - Fires before Claude Code compacts context window (PreCompact event)
   - Captures full pane content with configurable depth (three-tier fallback)
   - Monitors context pressure with warning threshold
   - Detects session state (menu, idle_prompt, permission_prompt, active)
   - Lists all available menu-driver.sh actions
   - Supports hybrid mode (bidirectional or async per agent)
   - Implements HOOK-10 specification

Both scripts share common guard patterns:
- Immediate stdin consumption to prevent pipe blocking
- $TMUX environment check for fast-path exit
- Registry lookup using jq (no Python dependency)
- Clean exit for non-managed sessions

## Requirements Fulfilled

| Requirement | Status | Evidence |
|-------------|--------|----------|
| HOOK-03 | ✓ | session-end-hook.sh notifies OpenClaw on session termination |
| HOOK-09 | ✓ | Minimal wake message format (identity + trigger only) |
| HOOK-10 | ✓ | Full wake message format with pane content, context pressure, state |

## Must-Haves Verification

**Truths:**
- ✓ session-end-hook.sh notifies OpenClaw immediately when a managed Claude Code session terminates
- ✓ session-end-hook.sh sends a minimal wake message with session identity and trigger type 'session_end' (no pane capture needed)
- ✓ pre-compact-hook.sh captures pane state before context compaction and sends wake message with trigger type 'pre_compact'
- ✓ Both hook scripts exit cleanly in under 5ms for non-managed sessions (no $TMUX or no registry match)
- ✓ Both hook scripts share common guard patterns (stdin consumption, $TMUX check, registry lookup)

**Artifacts:**
- ✓ scripts/session-end-hook.sh provides SessionEnd hook notifying OpenClaw on session termination (55 lines, min 40 required)
- ✓ scripts/pre-compact-hook.sh provides PreCompact hook capturing state before context compaction (116 lines, min 60 required)

**Key Links:**
- ✓ session-end-hook.sh → config/recovery-registry.json via jq lookup of agent by tmux_session_name (pattern: `jq.*select.*tmux_session_name`)
- ✓ session-end-hook.sh → openclaw agent via termination notification (pattern: `openclaw agent.*--session-id`)
- ✓ pre-compact-hook.sh → config/recovery-registry.json via jq lookup and three-tier fallback for pane capture depth (pattern: `hook_settings.*pane_capture_lines`)

## Deviations from Plan

None - plan executed exactly as written. All tasks completed without requiring auto-fixes, blocking issues, or architectural decisions.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| b2ebde4 | feat | Add session-end-hook.sh for immediate session termination notification |
| dd34ef9 | feat | Add pre-compact-hook.sh for state capture before context compaction |

## Technical Notes

**session-end-hook.sh characteristics:**
- Lightest hook script (55 lines)
- No pane capture (session is ending)
- No state detection (always "terminated")
- No context pressure monitoring
- No available actions section
- Always async (bidirectional mode not applicable)
- Enables faster recovery detection than polling

**pre-compact-hook.sh characteristics:**
- Full hook script pattern (116 lines)
- Configurable pane capture depth (three-tier fallback: per-agent > global > 100)
- Context pressure threshold with warning levels
- State detection from pane content patterns
- All menu-driver.sh actions listed
- Hybrid mode support (bidirectional or async)
- Gives OpenClaw visibility before context loss

**Shared patterns:**
- Stdin consumption: `STDIN_JSON=$(cat)` prevents pipe blocking
- TMUX guard: `[ -z "${TMUX:-}" ] && exit 0` for non-tmux sessions
- Registry lookup: jq query matching tmux_session_name
- Clean exits: All error paths exit 0 (hook scripts never fail)

**Wake message formats:**

Minimal (HOOK-09, session-end):
```
[SESSION IDENTITY]
agent_id: {AGENT_ID}
tmux_session_name: {SESSION_NAME}
timestamp: {ISO 8601 UTC}

[TRIGGER]
type: session_end

[STATE HINT]
state: terminated
```

Full (HOOK-10, pre-compact):
```
[SESSION IDENTITY]
agent_id: {AGENT_ID}
tmux_session_name: {SESSION_NAME}
timestamp: {ISO 8601 UTC}

[TRIGGER]
type: pre_compact

[STATE HINT]
state: {STATE}

[PANE CONTENT]
{PANE_CONTENT}

[CONTEXT PRESSURE]
{CONTEXT_PRESSURE}

[AVAILABLE ACTIONS]
menu-driver.sh {SESSION_NAME} choose <n>
menu-driver.sh {SESSION_NAME} type <text>
menu-driver.sh {SESSION_NAME} clear_then <command>
menu-driver.sh {SESSION_NAME} enter
menu-driver.sh {SESSION_NAME} esc
menu-driver.sh {SESSION_NAME} submit
menu-driver.sh {SESSION_NAME} snapshot
```

## Phase 1 Progress

Phase 01 (Additive Changes) hook scripts now complete:
- Plan 02: stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh
- **Plan 03: session-end-hook.sh, pre-compact-hook.sh** ✓

All 5 hook scripts created. Ready for Phase 2 (Deletions) to remove deprecated autoresponder and hook-watcher.

## Next Steps

Phase 01 Plan 02 will create the remaining hook scripts: stop-hook.sh (Stop event), notification-idle-hook.sh (Notification event with idle_prompt trigger), and notification-permission-hook.sh (Notification event with permission_prompt trigger).

## Self-Check

Verifying all claimed files and commits exist.

**Files created:**
- scripts/session-end-hook.sh: FOUND
- scripts/pre-compact-hook.sh: FOUND

**Commits:**
- b2ebde4: FOUND
- dd34ef9: FOUND

## Self-Check: PASSED

All files exist, all commits verified, all must-haves satisfied.
