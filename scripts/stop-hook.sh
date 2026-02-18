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

# stop-hook.sh - Claude Code Stop hook for managed GSD sessions
# Fires when Claude finishes responding. Captures state, sends wake message to OpenClaw agent.

# ============================================================================
# 1. CONSUME STDIN IMMEDIATELY (prevent pipe blocking)
# ============================================================================
STDIN_JSON=$(cat)
debug_log "stdin: ${#STDIN_JSON} bytes, hook_event_name=$(echo "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"

# ============================================================================
# 2. GUARD: stop_hook_active check (infinite loop prevention)
# ============================================================================
STOP_HOOK_ACTIVE=$(echo "$STDIN_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  debug_log "EXIT: stop_hook_active=true (infinite loop guard)"
  exit 0
fi

# ============================================================================
# 3. GUARD: $TMUX environment check (non-tmux sessions exit fast)
# ============================================================================
if [ -z "${TMUX:-}" ]; then
  debug_log "EXIT: TMUX env var is unset (not in tmux session)"
  exit 0
fi

# ============================================================================
# 4. EXTRACT tmux session name
# ============================================================================
SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
if [ -z "$SESSION_NAME" ]; then
  debug_log "EXIT: could not extract tmux session name"
  exit 0
fi
debug_log "tmux_session=$SESSION_NAME"
# Phase 2: redirect to per-session log file
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
debug_log "=== log redirected to per-session file ==="

# ============================================================================
# 5. REGISTRY LOOKUP (prefix match via shared function)
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_PATH="${SCRIPT_DIR}/../config/recovery-registry.json"

if [ ! -f "$REGISTRY_PATH" ]; then
  debug_log "EXIT: registry not found at $REGISTRY_PATH"
  exit 0
fi

LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
  debug_log "sourced lib/hook-utils.sh"
else
  debug_log "EXIT: hook-utils.sh not found at $LIB_PATH"
  exit 0
fi

AGENT_DATA=$(lookup_agent_in_registry "$REGISTRY_PATH" "$SESSION_NAME")

if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  debug_log "EXIT: no agent matched session=$SESSION_NAME in registry"
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
# 6. EXTRACT hook_settings with three-tier fallback
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
# 7. CAPTURE PANE CONTENT
# ============================================================================
PANE_CONTENT=$(tmux capture-pane -pt "${SESSION_NAME}:0.0" -S "-${PANE_CAPTURE_LINES}" 2>/dev/null || echo "")

# ============================================================================
# 7b. EXTRACT TRANSCRIPT CONTENT (primary source)
# ============================================================================
TRANSCRIPT_PATH=$(printf '%s' "$STDIN_JSON" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
EXTRACTED_RESPONSE=""

if type extract_last_assistant_response &>/dev/null; then
  EXTRACTED_RESPONSE=$(extract_last_assistant_response "$TRANSCRIPT_PATH")
  debug_log "transcript extraction: path=${TRANSCRIPT_PATH:-<empty>} result_length=${#EXTRACTED_RESPONSE}"
fi

# ============================================================================
# 8. DETECT STATE (pattern matching)
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
# 9. EXTRACT CONTEXT PRESSURE
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
# 9b. DETERMINE CONTENT: transcript (primary) or pane diff (fallback)
# ============================================================================
if [ -n "$EXTRACTED_RESPONSE" ]; then
  CONTENT_SECTION="$EXTRACTED_RESPONSE"
  debug_log "content source: transcript"
else
  # Fallback: pane diff from last 40 lines
  PANE_FOR_DIFF=$(printf '%s\n' "$PANE_CONTENT" | tail -40)
  if type extract_pane_diff &>/dev/null; then
    CONTENT_SECTION=$(extract_pane_diff "$SESSION_NAME" "$PANE_FOR_DIFF")
    debug_log "content source: pane_diff (delta_length=${#CONTENT_SECTION})"
  else
    # Ultimate fallback if lib not loaded: use raw pane tail
    CONTENT_SECTION=$(printf '%s\n' "$PANE_CONTENT" | tail -40)
    debug_log "content source: raw_pane_tail (lib not available)"
  fi
fi

# ============================================================================
# 10. BUILD STRUCTURED WAKE MESSAGE (v2 format)
# ============================================================================
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: response_complete

[CONTENT]
${CONTENT_SECTION}

[STATE HINT]
state: ${STATE}

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
# 11. HYBRID MODE DELIVERY
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
