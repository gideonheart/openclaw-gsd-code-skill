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
  echo "  4. tmux session existence and \$TMUX propagation"
  echo "  5. Session name resolution via tmux display-message"
  echo "  6. Registry lookup by session name"
  echo "  7. openclaw binary availability"
  echo "  8. Hook debug logs"
  echo "  9. JSONL log analysis (recent events, error counts, outcome distribution)"
  echo "  10. (Optional) Send a test wake message"
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
HOOK_LOG="${SKILL_ROOT}/logs"
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
# 9. Hook log directory
# ------------------------------------------------------------------
echo "--- Step 9: Hook Debug Logs ---"

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -d "$HOOK_LOG" ]; then
  LOG_FILE_COUNT=$(ls -1 "$HOOK_LOG"/*.log 2>/dev/null | wc -l || echo "0")
  pass "Log directory exists: $HOOK_LOG ($LOG_FILE_COUNT log files)"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  # Show session-specific log if it exists
  SESSION_LOG_FILE="${HOOK_LOG}/${TMUX_SESSION_NAME}.log"
  if [ -f "$SESSION_LOG_FILE" ]; then
    SESSION_LOG_LINES=$(wc -l < "$SESSION_LOG_FILE")
    LAST_ENTRY=$(tail -1 "$SESSION_LOG_FILE" 2>/dev/null || echo "")
    info "Session log: $SESSION_LOG_FILE ($SESSION_LOG_LINES lines)"
    info "Last entry: $LAST_ENTRY"
  else
    info "No session-specific log yet for $TMUX_SESSION_NAME"
  fi
else
  info "Log directory does not exist yet: $HOOK_LOG"
  info "It will be created when hooks fire"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))  # Not a failure
fi

echo ""

# ------------------------------------------------------------------
# 10. JSONL Log Analysis
# ------------------------------------------------------------------
echo "--- Step 10: JSONL Log Analysis ---"

JSONL_LOG_FILE="${HOOK_LOG}/${TMUX_SESSION_NAME}.jsonl"
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

if [ ! -f "$JSONL_LOG_FILE" ]; then
  info "No JSONL log yet for $TMUX_SESSION_NAME (hooks have not fired)"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
  JSONL_RECORD_COUNT=$(wc -l < "$JSONL_LOG_FILE" 2>/dev/null || echo "0")
  pass "JSONL log exists: $JSONL_LOG_FILE ($JSONL_RECORD_COUNT records)"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))

  echo ""
  info "Last 5 events:"
  jq -r '[.timestamp, .hook_script, .trigger, .outcome] | @tsv' "$JSONL_LOG_FILE" \
    2>/dev/null | tail -5 | while IFS=$'\t' read -r timestamp hook_script trigger outcome; do
    info "  $timestamp  $hook_script  $trigger  $outcome"
  done

  echo ""
  info "Outcome distribution:"
  jq -r '.outcome' "$JSONL_LOG_FILE" 2>/dev/null | sort | uniq -c | sort -rn | \
    while read -r count outcome; do
    info "  $count $outcome"
  done

  echo ""
  info "Hook script distribution:"
  jq -r '.hook_script' "$JSONL_LOG_FILE" 2>/dev/null | sort | uniq -c | sort -rn | \
    while read -r count hook_script; do
    info "  $count $hook_script"
  done

  echo ""
  NON_DELIVERED=$(jq -c 'select(.outcome != "delivered")' "$JSONL_LOG_FILE" 2>/dev/null | wc -l)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [ "$NON_DELIVERED" -gt 0 ]; then
    fail "Non-delivered events: $NON_DELIVERED — recent errors:"
    jq -r 'select(.outcome != "delivered") | [.timestamp, .hook_script, .outcome] | @tsv' \
      "$JSONL_LOG_FILE" 2>/dev/null | tail -5 | while IFS=$'\t' read -r timestamp hook_script outcome; do
      info "  $timestamp  $hook_script  $outcome"
    done
  else
    pass "No non-delivered events — all $JSONL_RECORD_COUNT hook invocations delivered"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  echo ""
  info "Duration stats (ms):"
  jq -s '[.[].duration_ms] | {count: length, min: min, max: max, avg: (add/length | round)}' \
    "$JSONL_LOG_FILE" 2>/dev/null | jq -r '"  count=\(.count) min=\(.min) max=\(.max) avg=\(.avg)"'
fi

echo ""

# ------------------------------------------------------------------
# 11. Optional: Send test wake message
# ------------------------------------------------------------------
if [ "$SEND_TEST_WAKE" = true ]; then
  echo "--- Step 11: Test Wake Message ---"

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
  echo "  2. Run: tail -f ${HOOK_LOG}/${TMUX_SESSION_NAME}.log"
  echo "  3. Trigger a Stop event (send a message to the Claude session)"
  echo "  4. Check the log for the exact failure point"
else
  FAILED=$((TOTAL_CHECKS - PASSED_CHECKS))
  echo "$FAILED check(s) failed. Fix the failures above, then re-run:"
  echo "  scripts/diagnose-hooks.sh $AGENT_NAME"
fi
echo ""
