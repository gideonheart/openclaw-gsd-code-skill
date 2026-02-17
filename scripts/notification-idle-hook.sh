#!/usr/bin/env bash
set -euo pipefail

# Debug logging - all hook invocations log to a shared file for diagnostics
GSD_HOOK_LOG="${GSD_HOOK_LOG:-/tmp/gsd-hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"

# notification-idle-hook.sh - Claude Code Notification hook for idle_prompt events
# Fires when Claude waits for user input. Captures state, sends wake message to OpenClaw agent.

# ============================================================================
# 1. CONSUME STDIN IMMEDIATELY (prevent pipe blocking)
# ============================================================================
STDIN_JSON=$(cat)
debug_log "stdin: ${#STDIN_JSON} bytes, hook_event_name=$(echo "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"

# NOTE: No stop_hook_active check - idle_prompt notifications don't cause infinite loops
# They fire once when idle, and only a user message or hook response triggers Claude to continue

# ============================================================================
# 2. GUARD: $TMUX environment check (non-tmux sessions exit fast)
# ============================================================================
if [ -z "${TMUX:-}" ]; then
  debug_log "EXIT: TMUX env var is unset (not in tmux session)"
  exit 0
fi

# ============================================================================
# 3. EXTRACT tmux session name
# ============================================================================
SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
if [ -z "$SESSION_NAME" ]; then
  debug_log "EXIT: could not extract tmux session name"
  exit 0
fi
debug_log "tmux_session=$SESSION_NAME"

# ============================================================================
# 4. REGISTRY LOOKUP (jq, no Python)
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_PATH="${SCRIPT_DIR}/../config/recovery-registry.json"

if [ ! -f "$REGISTRY_PATH" ]; then
  debug_log "EXIT: registry not found at $REGISTRY_PATH"
  exit 0
fi

AGENT_DATA=$(jq -r \
  --arg session "$SESSION_NAME" \
  '.agents[] | select(.tmux_session_name == $session) |
   {agent_id, openclaw_session_id, hook_settings}' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")

if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  debug_log "EXIT: no agent matched tmux_session_name=$SESSION_NAME in registry"
  exit 0  # Non-managed session, fast exit
fi

AGENT_ID=$(echo "$AGENT_DATA" | jq -r '.agent_id' 2>/dev/null || echo "")
OPENCLAW_SESSION_ID=$(echo "$AGENT_DATA" | jq -r '.openclaw_session_id' 2>/dev/null || echo "")
debug_log "agent_id=$AGENT_ID openclaw_session_id=$OPENCLAW_SESSION_ID"

if [ -z "$AGENT_ID" ] || [ -z "$OPENCLAW_SESSION_ID" ]; then
  debug_log "EXIT: agent_id or openclaw_session_id is empty"
  exit 0
fi

# ============================================================================
# 5. EXTRACT hook_settings with three-tier fallback
# ============================================================================
GLOBAL_SETTINGS=$(jq -r '.hook_settings // {}' "$REGISTRY_PATH" 2>/dev/null || echo "{}")

PANE_CAPTURE_LINES=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.pane_capture_lines // $global.pane_capture_lines // 100)' 2>/dev/null || echo "100")

CONTEXT_PRESSURE_THRESHOLD=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.context_pressure_threshold // $global.context_pressure_threshold // 50)' 2>/dev/null || echo "50")

HOOK_MODE=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.hook_mode // $global.hook_mode // "async")' 2>/dev/null || echo "async")

# ============================================================================
# 6. CAPTURE PANE CONTENT
# ============================================================================
PANE_CONTENT=$(tmux capture-pane -pt "${SESSION_NAME}:0.0" -S "-${PANE_CAPTURE_LINES}" 2>/dev/null || echo "")

# ============================================================================
# 7. DETECT STATE (pattern matching)
# ============================================================================
STATE="working"

if echo "$PANE_CONTENT" | grep -Eiq 'Enter to select|numbered.*option' 2>/dev/null; then
  STATE="menu"
elif echo "$PANE_CONTENT" | grep -Eiq 'permission|allow|dangerous' 2>/dev/null; then
  STATE="permission_prompt"
elif echo "$PANE_CONTENT" | grep -Eiq 'What can I help|waiting for' 2>/dev/null; then
  STATE="idle"
elif echo "$PANE_CONTENT" | grep -Ei 'error|failed|exception' 2>/dev/null | grep -v 'error handling' >/dev/null 2>&1; then
  STATE="error"
fi

debug_log "state=$STATE"

# ============================================================================
# 8. EXTRACT CONTEXT PRESSURE
# ============================================================================
PERCENTAGE=$(echo "$PANE_CONTENT" | tail -5 | grep -oE '[0-9]{1,3}%' | tail -1 | tr -d '%' 2>/dev/null || echo "")

if [ -n "$PERCENTAGE" ]; then
  if [ "$PERCENTAGE" -ge 80 ]; then
    CONTEXT_PRESSURE="${PERCENTAGE}% [CRITICAL]"
  elif [ "$PERCENTAGE" -ge "$CONTEXT_PRESSURE_THRESHOLD" ]; then
    CONTEXT_PRESSURE="${PERCENTAGE}% [WARNING]"
  else
    CONTEXT_PRESSURE="${PERCENTAGE}% [OK]"
  fi
else
  CONTEXT_PRESSURE="unknown"
fi

# ============================================================================
# 9. BUILD STRUCTURED WAKE MESSAGE
# ============================================================================
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: idle_prompt

[STATE HINT]
state: ${STATE}

[PANE CONTENT]
${PANE_CONTENT}

[CONTEXT PRESSURE]
${CONTEXT_PRESSURE}

[AVAILABLE ACTIONS]
menu-driver.sh ${SESSION_NAME} choose <n>
menu-driver.sh ${SESSION_NAME} type <text>
menu-driver.sh ${SESSION_NAME} clear_then <command>
menu-driver.sh ${SESSION_NAME} enter
menu-driver.sh ${SESSION_NAME} esc
menu-driver.sh ${SESSION_NAME} submit
menu-driver.sh ${SESSION_NAME} snapshot"

# ============================================================================
# 10. HYBRID MODE DELIVERY
# ============================================================================
debug_log "DELIVERING: mode=$HOOK_MODE session_id=$OPENCLAW_SESSION_ID"

if [ "$HOOK_MODE" = "bidirectional" ]; then
  # Synchronous mode: wait for OpenClaw response
  debug_log "DELIVERING: bidirectional, waiting for response..."
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" --json 2>&1 || echo "")
  debug_log "RESPONSE: ${RESPONSE:0:200}"

  # Parse response for decision injection
  if [ -n "$RESPONSE" ]; then
    DECISION=$(echo "$RESPONSE" | jq -r '.decision // ""' 2>/dev/null || echo "")
    REASON=$(echo "$RESPONSE" | jq -r '.reason // ""' 2>/dev/null || echo "")

    if [ "$DECISION" = "block" ] && [ -n "$REASON" ]; then
      # Return decision to Claude Code
      echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
    fi
  fi
  exit 0
else
  # Async mode (default): background call, exit immediately
  openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >> "$GSD_HOOK_LOG" 2>&1 &
  debug_log "DELIVERED (async, bg PID=$!)"
  exit 0
fi
