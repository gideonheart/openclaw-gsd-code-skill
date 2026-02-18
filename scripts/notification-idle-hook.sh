#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/hook-preamble.sh"

# notification-idle-hook.sh - Claude Code Notification hook for idle_prompt events
# Fires when Claude waits for user input. Captures state, sends wake message to OpenClaw agent.

# ============================================================================
# 1. CONSUME STDIN IMMEDIATELY (prevent pipe blocking)
# ============================================================================
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
debug_log "stdin: ${#STDIN_JSON} bytes, hook_event_name=$(printf '%s' "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"

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
# Phase 2: redirect to per-session log file
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
debug_log "=== log redirected to per-session file ==="

# ============================================================================
# 4. REGISTRY LOOKUP (prefix match via shared function)
# ============================================================================
if [ ! -f "$REGISTRY_PATH" ]; then
  debug_log "EXIT: registry not found at $REGISTRY_PATH"
  exit 0
fi

AGENT_DATA=$(lookup_agent_in_registry "$REGISTRY_PATH" "$SESSION_NAME")

if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  debug_log "EXIT: no agent matched session=$SESSION_NAME in registry"
  exit 0  # Non-managed session, fast exit
fi

AGENT_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.agent_id' 2>/dev/null || echo "")
OPENCLAW_SESSION_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.openclaw_session_id' 2>/dev/null || echo "")
debug_log "agent_id=$AGENT_ID openclaw_session_id=$OPENCLAW_SESSION_ID"

if [ -z "$AGENT_ID" ] || [ -z "$OPENCLAW_SESSION_ID" ]; then
  debug_log "EXIT: agent_id or openclaw_session_id is empty"
  exit 0
fi

# ============================================================================
# 5. EXTRACT hook_settings via shared function (three-tier fallback)
# ============================================================================
HOOK_SETTINGS_JSON=$(extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA")
PANE_CAPTURE_LINES=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.pane_capture_lines')
CONTEXT_PRESSURE_THRESHOLD=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.context_pressure_threshold')
HOOK_MODE=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.hook_mode')

# ============================================================================
# 6. CAPTURE PANE CONTENT
# ============================================================================
PANE_CONTENT=$(tmux capture-pane -pt "${SESSION_NAME}:0.0" -S "-${PANE_CAPTURE_LINES}" 2>/dev/null || echo "")

# ============================================================================
# 7. DETECT STATE (shared function — case-insensitive extended regex)
# ============================================================================
STATE=$(detect_session_state "$PANE_CONTENT")

debug_log "state=$STATE"

# ============================================================================
# 8. EXTRACT CONTEXT PRESSURE
# ============================================================================
PERCENTAGE=$(printf '%s\n' "$PANE_CONTENT" | tail -5 | grep -oE '[0-9]{1,3}%' | tail -1 | tr -d '%' 2>/dev/null || echo "")

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

[CONTENT]
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
TRIGGER="idle_prompt"
CONTENT_SOURCE="pane"
debug_log "DELIVERING: mode=$HOOK_MODE session_id=$OPENCLAW_SESSION_ID"

if [ "$HOOK_MODE" = "bidirectional" ]; then
  # Synchronous mode: wait for OpenClaw response
  debug_log "DELIVERING: bidirectional, waiting for response..."
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" --json 2>&1 || echo "")
  debug_log "RESPONSE: ${RESPONSE:0:200}"

  write_hook_event_record \
    "$JSONL_FILE" "$HOOK_ENTRY_MS" "$HOOK_SCRIPT_NAME" "$SESSION_NAME" \
    "$AGENT_ID" "$OPENCLAW_SESSION_ID" "$TRIGGER" "$STATE" \
    "$CONTENT_SOURCE" "$WAKE_MESSAGE" "$RESPONSE" "sync_delivered"

  # Parse response for decision injection
  if [ -n "$RESPONSE" ]; then
    DECISION=$(printf '%s' "$RESPONSE" | jq -r '.decision // ""' 2>/dev/null || echo "")
    REASON=$(printf '%s' "$RESPONSE" | jq -r '.reason // ""' 2>/dev/null || echo "")

    if [ "$DECISION" = "block" ] && [ -n "$REASON" ]; then
      # Return decision to Claude Code
      echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
    fi
  fi
  exit 0
else
  # Async mode (default): background call with JSONL logging
  deliver_async_with_logging \
    "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
    "$HOOK_SCRIPT_NAME" "$SESSION_NAME" "$AGENT_ID" \
    "$TRIGGER" "$STATE" "$CONTENT_SOURCE"
  debug_log "DELIVERED (async with JSONL logging)"
  exit 0
fi
