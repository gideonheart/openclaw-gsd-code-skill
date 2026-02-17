# Hook Behavior Specifications

This document provides full behavior specs for all 5 Claude Code hooks used by gsd-code-skill. Load this when hook behavior is unexpected or when configuring advanced hook settings.

All hooks are registered in `~/.claude/settings.json` via `scripts/register-hooks.sh`. All hooks share common patterns: consume stdin immediately, check `$TMUX` environment, lookup registry, exit cleanly in <5ms for non-managed sessions, use jq for all registry operations.

Hook settings use three-tier fallback: **per-agent** `agents[].hook_settings` > **global** top-level `hook_settings` > **hardcoded defaults** in hook scripts.

---

# Wake Hooks

These hooks notify the OpenClaw agent when Claude Code needs attention.

## stop-hook.sh

**Trigger:** Fires when Claude finishes responding (Stop event)

**What It Does:**

1. Consume stdin JSON to prevent pipe blocking
2. Check `stop_hook_active` guard (exit if `true` to prevent infinite loops)
3. Check `$TMUX` environment (exit if not in tmux)
4. Extract tmux session name via `tmux display-message -p '#S'`
5. Lookup agent entry in registry by matching `tmux_session_name`
6. Exit if no match (non-managed session)
7. Extract `hook_settings` with three-tier fallback (per-agent > global > hardcoded)
8. Capture pane content: `tmux capture-pane -pt <session> -S -<lines>`
9. Detect session state via pattern matching:
   - `menu` if pane contains "Enter to select" or "numbered.*option"
   - `permission_prompt` if pane contains "permission", "allow", or "dangerous"
   - `idle` if pane contains "What can I help" or "waiting for"
   - `error` if pane contains "error", "failed", or "exception" (excluding "error handling")
   - `working` otherwise
10. Extract context pressure: parse last 5 lines for `N%`, classify as CRITICAL (>=80%), WARNING (>=threshold), or OK
11. Build structured wake message with session identity, trigger type, state hint, pane content, context pressure, and available `menu-driver.sh` actions
12. Deliver message:
    - **Async mode** (default): background `openclaw agent` call, exit immediately
    - **Bidirectional mode**: wait for OpenClaw response, parse for `decision: "block"`, return decision to Claude Code

**Configuration (hook_settings):**

```json
{
  "pane_capture_lines": 100,
  "context_pressure_threshold": 50,
  "hook_mode": "async"
}
```

Defaults: `pane_capture_lines=100`, `context_pressure_threshold=50`, `hook_mode="async"`

**Edge Cases:**

- Exit if `stop_hook_active=true` in stdin JSON (prevents infinite loops when hook triggers itself)
- Exit if `$TMUX` is unset (non-tmux sessions)
- Exit if session name extraction fails
- Exit if registry file missing
- Exit if no agent entry matches session name
- Exit if `agent_id` or `openclaw_session_id` empty

**Exit Time:** <5ms for non-managed sessions, ~50-150ms for managed sessions (async mode), up to 600s timeout for bidirectional mode

**Related Registry Fields:** `tmux_session_name`, `agent_id`, `openclaw_session_id`, `hook_settings.pane_capture_lines`, `hook_settings.context_pressure_threshold`, `hook_settings.hook_mode`

---

## notification-idle-hook.sh

**Trigger:** Fires when Claude waits for user input (Notification event with `idle_prompt` matcher)

**What It Does:**

1. Consume stdin JSON to prevent pipe blocking
2. **No `stop_hook_active` check** (idle_prompt doesn't cause infinite loops)
3. Check `$TMUX` environment (exit if not in tmux)
4. Extract tmux session name via `tmux display-message -p '#S'`
5. Lookup agent entry in registry by matching `tmux_session_name`
6. Exit if no match (non-managed session)
7. Extract `hook_settings` with three-tier fallback
8. Capture pane content: `tmux capture-pane -pt <session> -S -<lines>`
9. Detect session state (same pattern matching as stop-hook.sh)
10. Extract context pressure (same logic as stop-hook.sh)
11. Build structured wake message with `type: idle_prompt`
12. Deliver message (async or bidirectional mode)

**Configuration (hook_settings):**

Same as stop-hook.sh: `pane_capture_lines`, `context_pressure_threshold`, `hook_mode`

**Edge Cases:**

- No `stop_hook_active` check (idle_prompt is one-shot, not recursive)
- Same registry guard conditions as stop-hook.sh
- Fires once when idle, only user message or hook response triggers Claude to continue

**Exit Time:** <5ms for non-managed sessions, ~50-150ms for managed sessions (async mode), up to 600s timeout for bidirectional mode

**Related Registry Fields:** Same as stop-hook.sh

---

## notification-permission-hook.sh

**Trigger:** Fires on permission dialogs (Notification event with `permission_prompt` matcher)

**What It Does:**

1-12. Identical flow to notification-idle-hook.sh, except wake message uses `type: permission_prompt`

**Configuration (hook_settings):**

Same as stop-hook.sh: `pane_capture_lines`, `context_pressure_threshold`, `hook_mode`

**Edge Cases:**

- No `stop_hook_active` check (permission_prompt is one-shot)
- Same registry guard conditions as stop-hook.sh
- Currently `--dangerously-skip-permissions` is used, so this hook rarely fires
- Future-proofing: enables intelligent permission handling when needed

**Exit Time:** <5ms for non-managed sessions, ~50-150ms for managed sessions (async mode), up to 600s timeout for bidirectional mode

**Related Registry Fields:** Same as stop-hook.sh

---

# Lifecycle Hooks

These hooks track session state without notifying agents.

## session-end-hook.sh

**Trigger:** Fires when Claude Code session terminates (SessionEnd event)

**What It Does:**

1. Consume stdin JSON to prevent pipe blocking
2. Check `$TMUX` environment (exit if not in tmux)
3. Extract tmux session name via `tmux display-message -p '#S'`
4. Lookup agent entry in registry by matching `tmux_session_name`
5. Exit if no match (non-managed session)
6. Build minimal wake message with session identity, `type: session_end`, `state: terminated`
7. **No pane capture** (session is terminating)
8. **No context pressure extraction**
9. Deliver message **always async** (bidirectional mode is meaningless for terminating sessions)

**Configuration (hook_settings):**

Uses default timeout (no custom timeout in settings.json registration). Ignores `hook_mode` (always async).

**Edge Cases:**

- Always async delivery (session terminating, can't wait for response)
- No pane content captured (session ending)
- No `stop_hook_active` check (SessionEnd doesn't recurse)

**Exit Time:** <5ms for non-managed sessions, ~30-50ms for managed sessions

**Related Registry Fields:** `tmux_session_name`, `agent_id`, `openclaw_session_id`

---

## pre-compact-hook.sh

**Trigger:** Fires before Claude Code compacts context window (PreCompact event)

**What It Does:**

1. Consume stdin JSON to prevent pipe blocking
2. Check `$TMUX` environment (exit if not in tmux)
3. Extract tmux session name via `tmux display-message -p '#S'`
4. Lookup agent entry in registry by matching `tmux_session_name`
5. Exit if no match (non-managed session)
6. Extract `hook_settings` with three-tier fallback
7. Capture pane content: `tmux capture-pane -t <session> -p -S -<lines>`
8. Extract context pressure percentage from last 5 lines: `grep -oP '\d+(?=% of context)'`
9. Classify pressure: above threshold = WARNING, otherwise OK
10. Detect session state via pattern matching:
    - `menu` if pane contains "Choose an option:"
    - `idle_prompt` if pane contains "Continue this conversation"
    - `permission_prompt` if pane contains "permission to"
    - `active` otherwise
11. Build structured wake message with `type: pre_compact`, state, pane content, context pressure, available actions
12. Deliver message (async or bidirectional mode)

**Configuration (hook_settings):**

```json
{
  "pane_capture_lines": 100,
  "context_pressure_threshold": 50,
  "hook_mode": "async"
}
```

Defaults: same as stop-hook.sh

**Edge Cases:**

- No `stop_hook_active` check (PreCompact doesn't recurse)
- No matcher in settings.json registration (fires on both auto and manual compact for full visibility)
- Same registry guard conditions as other hooks
- Timeout: 600s (matches Stop/Notification hooks)

**Exit Time:** <5ms for non-managed sessions, ~50-150ms for managed sessions (async mode), up to 600s timeout for bidirectional mode

**Related Registry Fields:** Same as stop-hook.sh

---

# Configuration Examples

## Minimal per-agent hook_settings

```json
{
  "agents": [
    {
      "agent_id": "gideon",
      "hook_settings": {
        "hook_mode": "bidirectional"
      }
    }
  ]
}
```

This agent uses bidirectional mode, inherits global `pane_capture_lines` and `context_pressure_threshold`.

## Global hook_settings with per-agent override

```json
{
  "hook_settings": {
    "pane_capture_lines": 150,
    "context_pressure_threshold": 60,
    "hook_mode": "async"
  },
  "agents": [
    {
      "agent_id": "warden",
      "hook_settings": {
        "pane_capture_lines": 200
      }
    },
    {
      "agent_id": "forge"
    }
  ]
}
```

- `warden` captures 200 lines, inherits threshold=60 and mode=async
- `forge` inherits all global settings (150 lines, threshold=60, async)

## All defaults (no hook_settings)

```json
{
  "agents": [
    {
      "agent_id": "scout"
    }
  ]
}
```

Uses hardcoded defaults: 100 lines, threshold=50, async mode.

---

# Troubleshooting

**Hook not firing:**
- Check `~/.claude/settings.json` has correct hook paths
- Restart Claude Code session after registration changes
- Verify hook scripts are executable: `chmod +x scripts/*.sh`

**Non-managed session getting hooked:**
- Check registry doesn't have entry with matching `tmux_session_name`
- Hooks exit fast for non-managed sessions (<5ms)

**Infinite loop / hook triggers itself:**
- Stop hook has `stop_hook_active` guard
- Notification/SessionEnd/PreCompact hooks don't need this guard (one-shot triggers)

**Bidirectional mode timeout:**
- Default timeout: 600s (Stop, Notification, PreCompact)
- SessionEnd has no timeout (always async)
- Increase timeout in `~/.claude/settings.json` if needed

**Hook fails silently:**
- Check registry file exists and is valid JSON
- Check `agent_id` and `openclaw_session_id` are non-empty
- Check tmux session exists: `tmux has-session -t <name>`
- All hook stderr goes to `/dev/null` in async mode
