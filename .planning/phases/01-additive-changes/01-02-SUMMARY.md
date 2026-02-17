---
phase: 01-additive-changes
plan: 02
subsystem: hook-scripts
tags: [hooks, event-driven, wake-messages, guards, hybrid-mode]
requires: [CONFIG-01, CONFIG-02, CONFIG-04, CONFIG-05, CONFIG-06, CONFIG-07, CONFIG-08, MENU-01]
provides: [HOOK-01, HOOK-02, HOOK-03, HOOK-04, HOOK-05, HOOK-06, HOOK-07, HOOK-08, HOOK-11, WAKE-01, WAKE-02, WAKE-03, WAKE-04, WAKE-05, WAKE-06]
affects: [hook-system, agent-orchestration, session-lifecycle]
tech_stack:
  added: []
  patterns: [guard-chain, three-tier-fallback, structured-wake-messages, hybrid-mode]
key_files:
  created:
    - scripts/stop-hook.sh
    - scripts/notification-idle-hook.sh
    - scripts/notification-permission-hook.sh
  modified: []
decisions: []
metrics:
  duration_minutes: 4
  completed_date: 2026-02-17
  task_count: 2
  file_count: 3
  commits: 2
---

# Phase 01 Plan 02: Hook Scripts with Wake Message System Summary

**One-liner:** Event-driven hook scripts (stop, idle_prompt, permission_prompt) that capture session state and send structured wake messages to OpenClaw agents via hybrid async/bidirectional mode.

## What Was Built

Created three production-ready hook scripts that transform Claude Code sessions from polling-based to event-driven intelligent orchestration:

1. **scripts/stop-hook.sh** - Stop hook for response completion events:
   - Consumes stdin immediately to prevent pipe blocking
   - Guards against infinite loops via `stop_hook_active` check
   - Fast-path exits for non-tmux sessions (<1ms via $TMUX check)
   - Registry lookup using jq with three-tier hook_settings fallback
   - Configurable pane capture depth (per-agent override via hook_settings.pane_capture_lines)
   - State detection via pattern matching (menu, idle, error, permission_prompt, working)
   - Context pressure extraction with threshold-based warning levels (OK, WARNING, CRITICAL)
   - Structured wake message with 6 sections: SESSION IDENTITY, TRIGGER, STATE HINT, PANE CONTENT, CONTEXT PRESSURE, AVAILABLE ACTIONS
   - Hybrid mode support: async default (background openclaw call), bidirectional per-agent (waits for decision injection)

2. **scripts/notification-idle-hook.sh** - Notification hook for idle_prompt events:
   - Same guard chain as stop-hook.sh (stdin, $TMUX, registry)
   - NO stop_hook_active check (not needed for notification hooks - they fire once when idle)
   - Trigger type: `idle_prompt` for agent differentiation
   - Same structured wake message format, state detection, context pressure, hybrid mode support

3. **scripts/notification-permission-hook.sh** - Notification hook for permission_prompt events:
   - Future-proofing: enables intelligent permission handling when --dangerously-skip-permissions is removed
   - Same guard chain, no stop_hook_active check
   - Trigger type: `permission_prompt`
   - Same structured wake message format, state detection, context pressure, hybrid mode support

All three scripts are standalone (SRP per locked decision), fully self-contained, and share common patterns but no source dependencies.

## Requirements Fulfilled

| Requirement | Status | Evidence |
|-------------|--------|----------|
| HOOK-01 | ✓ | stop-hook.sh fires on response completion, $TMUX check, registry lookup |
| HOOK-02 | ✓ | Pane capture with configurable depth, structured wake message, session ID routing |
| HOOK-03 | ✓ | Fast-path exits via $TMUX and registry miss (<5ms) |
| HOOK-04 | ✓ | stop_hook_active guard in stop-hook.sh, prevents infinite loops |
| HOOK-05 | ✓ | STDIN_JSON=$(cat) immediately in all three scripts |
| HOOK-06 | ✓ | Context pressure extraction via grep -oE, threshold comparison with OK/WARNING/CRITICAL |
| HOOK-07 | ✓ | notification-idle-hook.sh with trigger type idle_prompt |
| HOOK-08 | ✓ | notification-permission-hook.sh with trigger type permission_prompt |
| HOOK-11 | ✓ | Hybrid mode: async default, bidirectional via hook_settings.hook_mode |
| WAKE-01 | ✓ | Structured sections with [SECTION] markers in plain text |
| WAKE-02 | ✓ | Session identity (agent_id, tmux_session_name, timestamp) in every message |
| WAKE-03 | ✓ | State hint via pattern matching (5 states: menu, idle, permission_prompt, error, working) |
| WAKE-04 | ✓ | Trigger type differentiation (response_complete, idle_prompt, permission_prompt) |
| WAKE-05 | ✓ | Wake message always sent regardless of state (no conditional skipping) |
| WAKE-06 | ✓ | Context pressure as percentage + warning level against threshold |

## Must-Haves Verification

**Truths:**
- ✓ stop-hook.sh consumes stdin immediately, checks stop_hook_active, validates $TMUX, looks up agent in registry, captures pane content, detects state, extracts context pressure, builds structured wake message, and sends via async or bidirectional mode
- ✓ notification-idle-hook.sh fires on idle_prompt events with trigger type 'idle_prompt' and same wake message structure as stop-hook
- ✓ notification-permission-hook.sh fires on permission_prompt events with trigger type 'permission_prompt' and same wake message structure as stop-hook
- ✓ All three hook scripts exit cleanly in under 5ms for non-managed sessions (no $TMUX or no registry match)
- ✓ All three hook scripts support hybrid mode: async by default, bidirectional per-agent via hook_settings.hook_mode
- ✓ Wake messages contain all required sections: SESSION IDENTITY, TRIGGER, STATE HINT, PANE CONTENT, CONTEXT PRESSURE, AVAILABLE ACTIONS
- ✓ Context pressure shows percentage with warning level: OK below threshold, WARNING at threshold, CRITICAL at 80%+
- ✓ Stop hook has stop_hook_active infinite loop guard that exits immediately when field is true in stdin JSON

**Artifacts:**
- ✓ scripts/stop-hook.sh (169 lines, min 80 required)
- ✓ scripts/notification-idle-hook.sh (163 lines, min 60 required)
- ✓ scripts/notification-permission-hook.sh (164 lines, min 60 required)

**Key Links:**
- ✓ stop-hook.sh → config/recovery-registry.json (jq lookup of agent by tmux_session_name)
- ✓ stop-hook.sh → openclaw agent (wake message delivery via openclaw agent --session-id)
- ✓ stop-hook.sh → config/recovery-registry.json (three-tier fallback for hook_settings fields via jq --argjson)

## Deviations from Plan

None - plan executed exactly as written. All tasks completed without requiring auto-fixes, blocking issues, or architectural decisions.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 80298d3 | feat | Create stop-hook.sh with full guard chain and hybrid mode |
| 4769e0a | feat | Create notification hooks for idle and permission prompts |

## Technical Notes

**Guard chain execution order:**
1. Consume stdin immediately (HOOK-05) - prevents pipe blocking
2. Check stop_hook_active (HOOK-04, stop-hook.sh only) - prevents infinite loops
3. Check $TMUX environment (HOOK-03) - non-tmux sessions exit <1ms
4. Extract tmux session name - empty = exit
5. Registry lookup via jq (HOOK-01) - no match = exit (non-managed session)
6. Extract agent_id and openclaw_session_id - empty = exit

Total fast-path overhead for non-managed sessions: <5ms (verified during research).

**State detection patterns:**
- `menu`: matches "Enter to select" or "numbered.*option"
- `permission_prompt`: matches "permission", "allow", or "dangerous"
- `idle`: matches "What can I help" or "waiting for"
- `error`: matches "error", "failed", or "exception" BUT excludes lines with "error handling"
- `working`: default catch-all state

Patterns use grep -Eiq for case-insensitive extended regex.

**Context pressure calculation:**
- Extract last percentage from last 5 lines of pane content (statusline area)
- Compare against threshold (default 50, configurable via hook_settings.context_pressure_threshold)
- Levels: <threshold = OK, >=threshold = WARNING, >=80 = CRITICAL, not found = unknown

**Hybrid mode behavior:**
- `async` (default): Background openclaw call, exit 0 immediately (non-blocking)
- `bidirectional`: Synchronous openclaw call with --json, parse response for decision:block + reason, return to Claude Code for instruction injection

**DRY consideration:**
Per locked decision, scripts are separate (SRP) not shared-library. Each script is independently maintainable. The ~90% code duplication is intentional - different hook events have different lifecycle characteristics.

**No Python dependency:**
All JSON operations use jq 1.7 with --argjson and // fallback operators. Cross-platform, faster startup than Python, simpler deployment.

## Next Steps

Phase 01 Plan 03 will implement session-end-hook.sh and pre-compact-hook.sh to complete the hook script suite.

## Self-Check

Verifying all claimed files and commits exist.

**Files created:**
- scripts/stop-hook.sh: FOUND
- scripts/notification-idle-hook.sh: FOUND
- scripts/notification-permission-hook.sh: FOUND

**Commits:**
- 80298d3: FOUND
- 4769e0a: FOUND

**Verification checks:**
- All scripts pass bash -n syntax check: PASSED
- All scripts are executable: PASSED
- stop-hook.sh has stop_hook_active guard: PASSED
- Notification hooks have NO stop_hook_active logic: PASSED
- All scripts consume stdin immediately: PASSED
- All scripts have $TMUX guard: PASSED
- All scripts use jq (no Python): PASSED
- All scripts have 6-section wake messages: PASSED
- All scripts support hybrid mode: PASSED
- Trigger types correct (response_complete, idle_prompt, permission_prompt): PASSED

## Self-Check: PASSED

All files exist, all commits verified, all must-haves satisfied, all verification checks passed.
