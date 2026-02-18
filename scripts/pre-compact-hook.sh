#!/usr/bin/env bash
set -euo pipefail

# Resolve skill-local log directory from this script's location
SKILL_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$SKILL_LOG_DIR"

# Phase 1: log to shared file until session name is known
GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"

# PreCompact hook: Capture pane state before Claude Code compacts context window.
# Sends full wake message with pane content, context pressure, and available actions.
# Supports hybrid mode (async or bidirectional).

# 1. Consume stdin immediately to prevent pipe blocking
STDIN_JSON=$(cat)
debug_log "stdin: ${#STDIN_JSON} bytes, hook_event_name=$(echo "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"

# 2. Guard: Exit if not in tmux environment
if [ -z "${TMUX:-}" ]; then
  debug_log "EXIT: TMUX env var is unset (not in tmux session)"
  exit 0
fi

# 3. Extract tmux session name
SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
if [ -z "$SESSION_NAME" ]; then
  debug_log "EXIT: could not extract tmux session name"
  exit 0
fi
debug_log "tmux_session=$SESSION_NAME"
# Phase 2: redirect to per-session log file
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
debug_log "=== log redirected to per-session file ==="

# 4. Registry lookup (prefix match via shared function)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_PATH="${SCRIPT_DIR}/../config/recovery-registry.json"

if [ ! -f "$REGISTRY_PATH" ]; then
  debug_log "EXIT: registry not found at $REGISTRY_PATH"
  exit 0
fi

LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
else
  debug_log "EXIT: hook-utils.sh not found at $LIB_PATH"
  exit 0
fi

AGENT_DATA=$(lookup_agent_in_registry "$REGISTRY_PATH" "$SESSION_NAME")

if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  debug_log "EXIT: no agent matched session=$SESSION_NAME in registry"
  exit 0
fi

# Extract required fields
AGENT_ID=$(echo "$AGENT_DATA" | jq -r '.agent_id')
OPENCLAW_SESSION_ID=$(echo "$AGENT_DATA" | jq -r '.openclaw_session_id')
debug_log "agent_id=$AGENT_ID openclaw_session_id=$OPENCLAW_SESSION_ID"

if [ -z "$AGENT_ID" ] || [ -z "$OPENCLAW_SESSION_ID" ]; then
  debug_log "EXIT: agent_id or openclaw_session_id is empty"
  exit 0
fi

# 5. Extract hook_settings with three-tier fallback
GLOBAL_SETTINGS=$(jq -r '.hook_settings // {}' "$REGISTRY_PATH")

PANE_CAPTURE_LINES=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.pane_capture_lines // $global.pane_capture_lines // 100)')

CONTEXT_PRESSURE_THRESHOLD=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.context_pressure_threshold // $global.context_pressure_threshold // 50)')

HOOK_MODE=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.hook_mode // $global.hook_mode // "async")')

# 6. Capture pane content
PANE_CONTENT=$(tmux capture-pane -t "$SESSION_NAME:0.0" -p -S "-${PANE_CAPTURE_LINES}" 2>/dev/null || echo "")

# 7. Extract context pressure from last 5 lines
LAST_LINES=$(echo "$PANE_CONTENT" | tail -5)
CONTEXT_PRESSURE_PCT=$(echo "$LAST_LINES" | grep -oP '\d+(?=% of context)' | tail -1 || echo "0")

# Determine pressure level
if [ "$CONTEXT_PRESSURE_PCT" -ge "$CONTEXT_PRESSURE_THRESHOLD" ]; then
  CONTEXT_PRESSURE="at ${CONTEXT_PRESSURE_PCT}% (⚠ above ${CONTEXT_PRESSURE_THRESHOLD}% threshold)"
else
  CONTEXT_PRESSURE="at ${CONTEXT_PRESSURE_PCT}%"
fi

# 8. Detect session state from pane content
if echo "$PANE_CONTENT" | grep -q "Choose an option:"; then
  STATE="menu"
elif echo "$PANE_CONTENT" | grep -q "Continue this conversation"; then
  STATE="idle_prompt"
elif echo "$PANE_CONTENT" | grep -q "permission to"; then
  STATE="permission_prompt"
else
  STATE="active"
fi

debug_log "state=$STATE"

# 9. Build structured wake message (HOOK-10)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: pre_compact

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

# 10. Hybrid mode delivery
debug_log "DELIVERING: mode=$HOOK_MODE session_id=$OPENCLAW_SESSION_ID"

if [ "$HOOK_MODE" = "bidirectional" ]; then
  # Wait for OpenClaw response, return decision:block if provided
  debug_log "DELIVERING: bidirectional, waiting for response..."
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" --json 2>&1 || echo "")
  debug_log "RESPONSE: ${RESPONSE:0:200}"
  # Parse response for decision injection (future enhancement)
  exit 0
else
  # Async: background call, exit immediately
  openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >> "$GSD_HOOK_LOG" 2>&1 &
  debug_log "DELIVERED (async, bg PID=$!)"
  exit 0
fi
