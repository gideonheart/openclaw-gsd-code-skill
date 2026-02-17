---
phase: quick-4
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/stop-hook.sh
  - scripts/notification-idle-hook.sh
  - scripts/notification-permission-hook.sh
  - scripts/session-end-hook.sh
  - scripts/pre-compact-hook.sh
  - scripts/diagnose-hooks.sh
autonomous: true
requirements: []
must_haves:
  truths:
    - "All 5 hook scripts write timestamped debug logs to /tmp/gsd-hooks.log so operators can see whether hooks fire and where they fail"
    - "A diagnostic script can simulate the hook chain for any registered agent to verify: $TMUX propagation, session name resolution, registry lookup, and openclaw delivery"
    - "Hook scripts no longer silently swallow errors -- all failures are logged with the specific step that failed"
  artifacts:
    - path: "scripts/stop-hook.sh"
      provides: "Stop hook with debug logging"
      contains: "GSD_HOOK_LOG"
    - path: "scripts/notification-idle-hook.sh"
      provides: "Idle notification hook with debug logging"
      contains: "GSD_HOOK_LOG"
    - path: "scripts/notification-permission-hook.sh"
      provides: "Permission notification hook with debug logging"
      contains: "GSD_HOOK_LOG"
    - path: "scripts/session-end-hook.sh"
      provides: "Session end hook with debug logging"
      contains: "GSD_HOOK_LOG"
    - path: "scripts/pre-compact-hook.sh"
      provides: "Pre-compact hook with debug logging"
      contains: "GSD_HOOK_LOG"
    - path: "scripts/diagnose-hooks.sh"
      provides: "End-to-end hook chain diagnostic script"
      contains: "diagnose"
  key_links:
    - from: "scripts/stop-hook.sh"
      to: "/tmp/gsd-hooks.log"
      via: "debug_log function appending to log file"
      pattern: "GSD_HOOK_LOG"
    - from: "scripts/diagnose-hooks.sh"
      to: "config/recovery-registry.json"
      via: "jq registry lookup to simulate hook chain"
      pattern: "recovery-registry.json"
---

<objective>
Add debug logging to all 5 hook scripts and create a diagnostic script to identify why hooks are not detecting/responding to Claude Code events from tmux sessions.

Purpose: The hook system (stop-hook.sh, notification-idle-hook.sh, etc.) should fire when Claude Code produces output or waits for input in a tmux session. After quick task 3 fixed the TUI interaction and first-command delivery, the spawned agent now starts working but then stops after thinking -- the hook system never wakes the orchestrating agent. There is currently zero observability into whether hooks fire at all, whether they identify the correct tmux session, whether registry lookup succeeds, or whether the openclaw delivery call works. This task adds debug logging to every hook and a diagnostic script to test the chain end-to-end.

Output: All 5 hook scripts with debug logging, plus a new diagnose-hooks.sh script.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@scripts/stop-hook.sh
@scripts/notification-idle-hook.sh
@scripts/notification-permission-hook.sh
@scripts/session-end-hook.sh
@scripts/pre-compact-hook.sh
@config/recovery-registry.json
@docs/hooks.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add debug logging to all 5 hook scripts</name>
  <files>scripts/stop-hook.sh, scripts/notification-idle-hook.sh, scripts/notification-permission-hook.sh, scripts/session-end-hook.sh, scripts/pre-compact-hook.sh</files>
  <action>
Add a shared debug logging mechanism to all 5 hook scripts. The goal is to see exactly where each hook execution gets to, what values it sees, and where it exits (either successfully or via a guard).

**Step 1: Add debug_log function and GSD_HOOK_LOG variable to each hook script.**

Add this block immediately AFTER the shebang and `set -euo pipefail`, BEFORE any other code, in ALL 5 scripts:

```bash
# Debug logging - all hook invocations log to a shared file for diagnostics
GSD_HOOK_LOG="${GSD_HOOK_LOG:-/tmp/gsd-hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" >> "$GSD_HOOK_LOG" 2>/dev/null || true
}
```

**Step 2: Add log statements at every critical decision point in each hook.**

For ALL 5 hook scripts, add `debug_log` calls at these points (adapt the message to each hook's specific event name):

a) Immediately after the debug_log function definition:
```bash
debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"
```

b) After reading stdin JSON (step 1 in each hook), log the raw stdin length and key fields:
```bash
debug_log "stdin: ${#STDIN_JSON} bytes, hook_event_name=$(echo "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"
```

c) At EVERY `exit 0` guard point, add a log BEFORE the exit explaining WHY the hook is exiting early. Examples:

For the stop_hook_active guard (stop-hook.sh only):
```bash
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  debug_log "EXIT: stop_hook_active=true (infinite loop guard)"
  exit 0
fi
```

For the $TMUX guard (all hooks):
```bash
if [ -z "${TMUX:-}" ]; then
  debug_log "EXIT: TMUX env var is unset (not in tmux session)"
  exit 0
fi
```

For the session name extraction:
```bash
SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
if [ -z "$SESSION_NAME" ]; then
  debug_log "EXIT: could not extract tmux session name"
  exit 0
fi
debug_log "tmux_session=$SESSION_NAME"
```

For the registry file check:
```bash
if [ ! -f "$REGISTRY_PATH" ]; then
  debug_log "EXIT: registry not found at $REGISTRY_PATH"
  exit 0
fi
```

For the agent data lookup:
```bash
# After AGENT_DATA query:
if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  debug_log "EXIT: no agent matched tmux_session_name=$SESSION_NAME in registry"
  exit 0
fi
debug_log "agent_id=$AGENT_ID openclaw_session_id=$OPENCLAW_SESSION_ID"
```

For the agent_id/openclaw_session_id empty check:
```bash
if [ -z "$AGENT_ID" ] || [ -z "$OPENCLAW_SESSION_ID" ]; then
  debug_log "EXIT: agent_id or openclaw_session_id is empty"
  exit 0
fi
```

d) After state detection:
```bash
debug_log "state=$STATE"
```

e) Before the openclaw delivery call (at the end of each hook):
```bash
debug_log "DELIVERING: mode=$HOOK_MODE session_id=$OPENCLAW_SESSION_ID"
```

f) After the openclaw delivery (capture exit code instead of discarding):

For **async mode**, change:
```bash
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >/dev/null 2>&1 &
```
to:
```bash
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >> "$GSD_HOOK_LOG" 2>&1 &
debug_log "DELIVERED (async, bg PID=$!)"
```

For **bidirectional mode**, add logging around the openclaw call:
```bash
debug_log "DELIVERING: bidirectional, waiting for response..."
RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" --json 2>&1 || echo "")
debug_log "RESPONSE: ${RESPONSE:0:200}"
```

**Step 3: Apply to all 5 hook scripts.**

- **stop-hook.sh**: All of the above including the stop_hook_active guard log.
- **notification-idle-hook.sh**: Same as above but skip stop_hook_active guard (it doesn't have one). Log the hook_event_name as "Notification:idle_prompt".
- **notification-permission-hook.sh**: Same as notification-idle-hook.sh but log as "Notification:permission_prompt".
- **session-end-hook.sh**: Same pattern but simpler (no hook_settings extraction, no state detection, always async). Log as "SessionEnd".
- **pre-compact-hook.sh**: Same full pattern. Log as "PreCompact".

**CRITICAL: Do NOT change the actual hook logic, control flow, or openclaw message format.** Only ADD debug_log calls and change the openclaw async call to log output instead of discarding it. The hooks must continue to function identically -- logging is purely additive.

**CRITICAL: The debug_log function must use `>> "$GSD_HOOK_LOG" 2>/dev/null || true` to ensure logging failures never crash the hook (the `|| true` prevents set -e from killing the script if the log write fails).**
  </action>
  <verify>
Run `bash -n scripts/stop-hook.sh && bash -n scripts/notification-idle-hook.sh && bash -n scripts/notification-permission-hook.sh && bash -n scripts/session-end-hook.sh && bash -n scripts/pre-compact-hook.sh` to confirm all 5 pass syntax check.

Run `grep -c 'debug_log' scripts/stop-hook.sh` -- should return 10+ (one per decision point).
Run `grep -c 'debug_log' scripts/notification-idle-hook.sh` -- should return 8+ .
Run `grep -c 'GSD_HOOK_LOG' scripts/stop-hook.sh` -- should return 2+ (variable definition + usage in debug_log).
Run `grep 'exit 0' scripts/stop-hook.sh | head -5` -- every `exit 0` should have a nearby `debug_log` call.
  </verify>
  <done>
All 5 hook scripts have debug logging at every decision point. Running `tail -f /tmp/gsd-hooks.log` while a managed Claude Code session is active will show exactly whether hooks fire, what session name they resolve, whether registry lookup matches, and whether openclaw delivery succeeds or fails. No hook logic or message format has changed.
  </done>
</task>

<task type="auto">
  <name>Task 2: Create diagnose-hooks.sh diagnostic script</name>
  <files>scripts/diagnose-hooks.sh</files>
  <action>
Create a new script `scripts/diagnose-hooks.sh` that tests the entire hook chain step-by-step for a given agent, without waiting for Claude Code to naturally trigger an event. This is for operators to run manually to diagnose hook failures.

The script should:
1. Accept an agent name as argument (required)
2. Test each step of the hook chain independently
3. Report PASS/FAIL for each step with diagnostic details
4. Optionally send a test wake message to verify openclaw delivery

```bash
#!/usr/bin/env bash
set -euo pipefail

# diagnose-hooks.sh - Test the complete hook chain for a registered agent
# Usage: scripts/diagnose-hooks.sh <agent-name> [--send-test-wake]

log_message() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
info() { printf '  \033[36mINFO\033[0m %s\n' "$*"; }

AGENT_NAME="${1:-}"
SEND_TEST_WAKE=false

if [ -z "$AGENT_NAME" ]; then
  echo "Usage: diagnose-hooks.sh <agent-name> [--send-test-wake]"
  echo ""
  echo "Tests the complete hook chain for a registered agent:"
  echo "  1. Hook registration in ~/.claude/settings.json"
  echo "  2. Hook script existence and executability"
  echo "  3. Agent registry entry and required fields"
  echo "  4. tmux session existence and $TMUX propagation"
  echo "  5. Session name resolution via tmux display-message"
  echo "  6. Registry lookup by session name"
  echo "  7. openclaw binary availability"
  echo "  8. (Optional) Send a test wake message"
  echo ""
  echo "Options:"
  echo "  --send-test-wake   Actually send a test wake message via openclaw"
  exit 1
fi

shift
while [ $# -gt 0 ]; do
  case "$1" in
    --send-test-wake) SEND_TEST_WAKE=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_PATH="${SKILL_ROOT}/config/recovery-registry.json"
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_LOG="/tmp/gsd-hooks.log"
TOTAL_CHECKS=0
PASSED_CHECKS=0

check() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if "$@"; then
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    return 0
  fi
  return 1
}

echo ""
echo "=========================================="
echo "  GSD Hook Chain Diagnostic"
echo "  Agent: $AGENT_NAME"
echo "  Time:  $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "=========================================="
echo ""

# ------------------------------------------------------------------
# 1. Hook registration in settings.json
# ------------------------------------------------------------------
echo "--- Step 1: Hook Registration ---"

if [ ! -f "$SETTINGS_FILE" ]; then
  fail "Settings file not found: $SETTINGS_FILE"
else
  HOOK_EVENTS=("Stop" "Notification" "SessionEnd" "PreCompact")
  for event_name in "${HOOK_EVENTS[@]}"; do
    REGISTERED=$(jq -r --arg event_key "$event_name" '.hooks[$event_key] // empty' "$SETTINGS_FILE" 2>/dev/null)
    if [ -n "$REGISTERED" ]; then
      pass "$event_name hook registered"
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
      fail "$event_name hook NOT registered"
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  done
fi

echo ""

# ------------------------------------------------------------------
# 2. Hook scripts exist and are executable
# ------------------------------------------------------------------
echo "--- Step 2: Hook Script Files ---"

HOOK_SCRIPTS=(
  "stop-hook.sh"
  "notification-idle-hook.sh"
  "notification-permission-hook.sh"
  "session-end-hook.sh"
  "pre-compact-hook.sh"
)

for script_name in "${HOOK_SCRIPTS[@]}"; do
  SCRIPT_PATH="${SKILL_ROOT}/scripts/${script_name}"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [ -f "$SCRIPT_PATH" ] && [ -x "$SCRIPT_PATH" ]; then
    pass "$script_name exists and is executable"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  elif [ -f "$SCRIPT_PATH" ]; then
    fail "$script_name exists but is NOT executable (run: chmod +x $SCRIPT_PATH)"
  else
    fail "$script_name NOT FOUND at $SCRIPT_PATH"
  fi
done

echo ""

# ------------------------------------------------------------------
# 3. Agent registry entry
# ------------------------------------------------------------------
echo "--- Step 3: Agent Registry Entry ---"

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ ! -f "$REGISTRY_PATH" ]; then
  fail "Registry file not found: $REGISTRY_PATH"
else
  pass "Registry file exists"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))

  AGENT_ENTRY=$(jq -c --arg agent_id "$AGENT_NAME" \
    '.agents[] | select(.agent_id == $agent_id)' \
    "$REGISTRY_PATH" 2>/dev/null || echo "")

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [ -z "$AGENT_ENTRY" ]; then
    fail "No agent entry found for agent_id='$AGENT_NAME'"
    echo ""
    echo "Available agents:"
    jq -r '.agents[].agent_id' "$REGISTRY_PATH" 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "Cannot continue diagnostics without agent entry."
    exit 1
  else
    pass "Agent entry found for '$AGENT_NAME'"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # Check required fields
  TMUX_SESSION_NAME=$(echo "$AGENT_ENTRY" | jq -r '.tmux_session_name // ""')
  OPENCLAW_SESSION_ID=$(echo "$AGENT_ENTRY" | jq -r '.openclaw_session_id // ""')
  AGENT_ID=$(echo "$AGENT_ENTRY" | jq -r '.agent_id // ""')

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [ -n "$TMUX_SESSION_NAME" ]; then
    pass "tmux_session_name = $TMUX_SESSION_NAME"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    fail "tmux_session_name is empty"
  fi

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [ -n "$OPENCLAW_SESSION_ID" ]; then
    pass "openclaw_session_id = $OPENCLAW_SESSION_ID"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    fail "openclaw_session_id is empty"
  fi
fi

echo ""

# ------------------------------------------------------------------
# 4. tmux session existence
# ------------------------------------------------------------------
echo "--- Step 4: tmux Session ---"

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
  pass "tmux session '$TMUX_SESSION_NAME' exists"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
  fail "tmux session '$TMUX_SESSION_NAME' does NOT exist"
  info "Active sessions:"
  tmux list-sessions 2>/dev/null | sed 's/^/    /' || info "  (no tmux sessions)"
fi

echo ""

# ------------------------------------------------------------------
# 5. $TMUX environment propagation
# ------------------------------------------------------------------
echo "--- Step 5: TMUX Environment Propagation ---"

# Check if the Claude Code process running in that tmux session has $TMUX set
# Find PID of the claude process in the target tmux session
TARGET_PTS=$(tmux display-message -t "${TMUX_SESSION_NAME}:0.0" -p '#{pane_tty}' 2>/dev/null || echo "")

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -z "$TARGET_PTS" ]; then
  fail "Could not determine pane TTY for session $TMUX_SESSION_NAME"
else
  # Find claude process on that TTY
  TARGET_PTS_SHORT=$(basename "$TARGET_PTS")
  CLAUDE_PID=$(ps aux | grep "claude" | grep "$TARGET_PTS_SHORT" | grep -v grep | awk '{print $2}' | head -1 || echo "")

  if [ -z "$CLAUDE_PID" ]; then
    fail "No claude process found on $TARGET_PTS (session may not have Claude running)"
    info "Processes on $TARGET_PTS:"
    ps aux | grep "$TARGET_PTS_SHORT" | grep -v grep | sed 's/^/    /' || true
  else
    TMUX_ENV_VALUE=$(cat "/proc/$CLAUDE_PID/environ" 2>/dev/null | tr '\0' '\n' | grep '^TMUX=' || echo "")
    if [ -n "$TMUX_ENV_VALUE" ]; then
      pass "Claude PID $CLAUDE_PID has $TMUX_ENV_VALUE"
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
      fail "Claude PID $CLAUDE_PID does NOT have TMUX in its environment"
      info "This means hooks will exit at the TMUX guard and never reach registry lookup"
    fi
  fi
fi

echo ""

# ------------------------------------------------------------------
# 6. Session name resolution (simulating what hook scripts do)
# ------------------------------------------------------------------
echo "--- Step 6: Session Name Resolution ---"

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
# The hook scripts use: tmux display-message -p '#S'
# This gets the session name for the current client. In the context of the hook,
# the "current" client is determined by the $TMUX env var.
# We can simulate this by running it targeted at the session:
RESOLVED_NAME=$(tmux display-message -t "${TMUX_SESSION_NAME}:0.0" -p '#S' 2>/dev/null || echo "")
if [ -n "$RESOLVED_NAME" ]; then
  pass "tmux display-message resolves to: $RESOLVED_NAME"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [ "$RESOLVED_NAME" = "$TMUX_SESSION_NAME" ]; then
    pass "Resolved name matches registry tmux_session_name"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    fail "Resolved name '$RESOLVED_NAME' does NOT match registry '$TMUX_SESSION_NAME'"
    info "This mismatch means the registry lookup will fail to find the agent"
  fi
else
  fail "tmux display-message failed for session $TMUX_SESSION_NAME"
fi

echo ""

# ------------------------------------------------------------------
# 7. Registry lookup by session name (simulating hook logic)
# ------------------------------------------------------------------
echo "--- Step 7: Registry Lookup by Session Name ---"

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
LOOKUP_RESULT=$(jq -c --arg session "$TMUX_SESSION_NAME" \
  '.agents[] | select(.tmux_session_name == $session) | {agent_id, openclaw_session_id}' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")

if [ -n "$LOOKUP_RESULT" ] && [ "$LOOKUP_RESULT" != "null" ]; then
  LOOKUP_AGENT=$(echo "$LOOKUP_RESULT" | jq -r '.agent_id')
  LOOKUP_SESSION=$(echo "$LOOKUP_RESULT" | jq -r '.openclaw_session_id')
  pass "Registry lookup matched: agent_id=$LOOKUP_AGENT, session_id=$LOOKUP_SESSION"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
  fail "Registry lookup found NO agent with tmux_session_name=$TMUX_SESSION_NAME"
  info "This is the exact query the hook scripts use -- if this fails, hooks will exit silently"
fi

echo ""

# ------------------------------------------------------------------
# 8. openclaw binary
# ------------------------------------------------------------------
echo "--- Step 8: openclaw Binary ---"

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_PATH=$(command -v openclaw)
  OPENCLAW_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
  pass "openclaw found at $OPENCLAW_PATH (version: $OPENCLAW_VERSION)"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
  fail "openclaw binary NOT found in PATH"
  info "Hook scripts call 'openclaw agent --session-id ... --message ...' to deliver wake messages"
  info "Without openclaw in PATH, hooks fire but delivery fails silently"
fi

echo ""

# ------------------------------------------------------------------
# 9. Hook log file
# ------------------------------------------------------------------
echo "--- Step 9: Hook Debug Log ---"

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -f "$HOOK_LOG" ]; then
  HOOK_LOG_LINES=$(wc -l < "$HOOK_LOG")
  LAST_ENTRY=$(tail -1 "$HOOK_LOG" 2>/dev/null || echo "")
  pass "Hook log exists: $HOOK_LOG ($HOOK_LOG_LINES lines)"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  info "Last entry: $LAST_ENTRY"
else
  info "Hook log does not exist yet: $HOOK_LOG"
  info "It will be created when hooks fire after debug logging is added"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))  # Not a failure, just not created yet
fi

echo ""

# ------------------------------------------------------------------
# 10. Optional: Send test wake message
# ------------------------------------------------------------------
if [ "$SEND_TEST_WAKE" = true ]; then
  echo "--- Step 10: Test Wake Message ---"

  TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  TEST_WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${TMUX_SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: diagnostic_test

[STATE HINT]
state: diagnostic

[DIAGNOSTIC]
This is a test message from diagnose-hooks.sh to verify openclaw delivery."

  info "Sending test wake message to openclaw session $OPENCLAW_SESSION_ID ..."

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  DELIVERY_OUTPUT=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$TEST_WAKE_MESSAGE" 2>&1 || echo "DELIVERY_FAILED")

  if echo "$DELIVERY_OUTPUT" | grep -qi "failed\|error\|not found"; then
    fail "openclaw delivery failed: $DELIVERY_OUTPUT"
  else
    pass "openclaw delivery succeeded: $DELIVERY_OUTPUT"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  echo ""
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo "=========================================="
echo "  Results: $PASSED_CHECKS/$TOTAL_CHECKS checks passed"
echo "=========================================="
echo ""

if [ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]; then
  echo "All checks passed. If hooks still aren't working:"
  echo "  1. Restart the Claude Code session (hooks snapshot at startup)"
  echo "  2. Run: tail -f $HOOK_LOG"
  echo "  3. Trigger a Stop event (send a message to the Claude session)"
  echo "  4. Check the log for the exact failure point"
else
  FAILED=$((TOTAL_CHECKS - PASSED_CHECKS))
  echo "$FAILED check(s) failed. Fix the failures above, then re-run:"
  echo "  scripts/diagnose-hooks.sh $AGENT_NAME"
fi
echo ""
```

Make the script executable: `chmod +x scripts/diagnose-hooks.sh`

**Design decisions:**
- The script does NOT require being run inside tmux (unlike the hook scripts). It tests FROM OUTSIDE.
- It simulates the exact lookup logic the hooks use (jq query by tmux_session_name).
- Step 5 checks TMUX env propagation by reading /proc/PID/environ of the claude process -- this is the most likely failure point.
- The --send-test-wake flag is opt-in to avoid spamming the openclaw agent during diagnostics.
- All output uses colored PASS/FAIL/INFO for quick scanning.
  </action>
  <verify>
Run `bash -n scripts/diagnose-hooks.sh` to confirm no syntax errors.
Run `chmod +x scripts/diagnose-hooks.sh && ls -la scripts/diagnose-hooks.sh` to confirm it is executable.
Run `scripts/diagnose-hooks.sh --help 2>&1 || scripts/diagnose-hooks.sh 2>&1 | head -5` to confirm usage message displays.
Run `scripts/diagnose-hooks.sh warden 2>&1 | head -30` to confirm it runs the diagnostic chain (may show failures if warden session isn't active, which is fine -- the script should still run without crashing).
  </verify>
  <done>
diagnose-hooks.sh exists, is executable, accepts an agent name, and tests all 10 steps of the hook chain with PASS/FAIL output. An operator can run `scripts/diagnose-hooks.sh warden` to immediately see where the hook chain breaks, then `tail -f /tmp/gsd-hooks.log` to watch hooks fire in real time after the debug logging from Task 1 is deployed.
  </done>
</task>

</tasks>

<verification>
1. `bash -n scripts/stop-hook.sh && bash -n scripts/notification-idle-hook.sh && bash -n scripts/notification-permission-hook.sh && bash -n scripts/session-end-hook.sh && bash -n scripts/pre-compact-hook.sh && bash -n scripts/diagnose-hooks.sh` -- all 6 scripts pass syntax check
2. `grep -l 'GSD_HOOK_LOG' scripts/*hook*.sh | wc -l` -- returns 5 (all hook scripts have debug logging)
3. `grep -l 'debug_log' scripts/*hook*.sh | wc -l` -- returns 5 (all hook scripts use debug_log)
4. `ls -la scripts/diagnose-hooks.sh` -- exists and is executable
5. After restarting a Claude Code session in a managed tmux session, `tail -f /tmp/gsd-hooks.log` shows hook firing events with session name, agent lookup results, and delivery status
</verification>

<success_criteria>
- All 5 hook scripts log to /tmp/gsd-hooks.log at every decision point (TMUX guard, session name, registry lookup, openclaw delivery)
- diagnose-hooks.sh runs end-to-end for a registered agent and reports PASS/FAIL for each step
- No changes to actual hook logic -- debug logging is purely additive
- Running `scripts/diagnose-hooks.sh warden` immediately shows where the hook chain breaks
- After deploying, `tail -f /tmp/gsd-hooks.log` during a Claude Code session provides full visibility into hook behavior
</success_criteria>

<output>
After completion, create `.planning/quick/4-fix-hook-system-to-detect-and-respond-to/4-SUMMARY.md`
</output>
