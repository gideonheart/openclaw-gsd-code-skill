#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/hook-preamble.sh"

# PreCompact hook: Capture pane state before Claude Code compacts context window.
# Sends full wake message with pane content, context pressure, and available actions.
# Supports hybrid mode (async or bidirectional).

# 1. Consume stdin immediately to prevent pipe blocking
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
debug_log "stdin: ${#STDIN_JSON} bytes, hook_event_name=$(printf '%s' "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"

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
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
debug_log "=== log redirected to per-session file ==="

# 4. Registry lookup (prefix match via shared function)
if [ ! -f "$REGISTRY_PATH" ]; then
  debug_log "EXIT: registry not found at $REGISTRY_PATH"
  exit 0
fi

AGENT_DATA=$(lookup_agent_in_registry "$REGISTRY_PATH" "$SESSION_NAME")

if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  debug_log "EXIT: no agent matched session=$SESSION_NAME in registry"
  exit 0
fi

# Extract required fields
AGENT_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.agent_id' 2>/dev/null || echo "")
OPENCLAW_SESSION_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.openclaw_session_id' 2>/dev/null || echo "")
debug_log "agent_id=$AGENT_ID openclaw_session_id=$OPENCLAW_SESSION_ID"

if [ -z "$AGENT_ID" ] || [ -z "$OPENCLAW_SESSION_ID" ]; then
  debug_log "EXIT: agent_id or openclaw_session_id is empty"
  exit 0
fi

# 5. Extract hook_settings via shared function (three-tier fallback)
HOOK_SETTINGS_JSON=$(extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA")
PANE_CAPTURE_LINES=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.pane_capture_lines')
CONTEXT_PRESSURE_THRESHOLD=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.context_pressure_threshold')
HOOK_MODE=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.hook_mode')

# 6. Capture pane content
PANE_CONTENT=$(tmux capture-pane -t "$SESSION_NAME:0.0" -p -S "-${PANE_CAPTURE_LINES}" 2>/dev/null || echo "")

# 7. Extract context pressure from last 5 lines
LAST_LINES=$(printf '%s\n' "$PANE_CONTENT" | tail -5)
CONTEXT_PRESSURE_PCT=$(printf '%s\n' "$LAST_LINES" | grep -oP '\d+(?=% of context)' | tail -1 || echo "0")

# Determine pressure level
if [ "$CONTEXT_PRESSURE_PCT" -ge "$CONTEXT_PRESSURE_THRESHOLD" ]; then
  CONTEXT_PRESSURE="at ${CONTEXT_PRESSURE_PCT}% (warning: above ${CONTEXT_PRESSURE_THRESHOLD}% threshold)"
else
  CONTEXT_PRESSURE="at ${CONTEXT_PRESSURE_PCT}%"
fi

# 8. Detect session state (shared function — case-insensitive extended regex)
STATE=$(detect_session_state "$PANE_CONTENT")

debug_log "state=$STATE"

# 9. Build structured wake message
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
MENU_DRIVER_PATH="${_GSD_SKILL_ROOT}/scripts/menu-driver.sh"
SCRIPT_DIR="${_GSD_SKILL_ROOT}/scripts"
ACTION_PROMPT=$(load_hook_prompt "pre-compact" "$SESSION_NAME" "$MENU_DRIVER_PATH" "$SCRIPT_DIR")

WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: pre_compact

[STATE HINT]
state: ${STATE}

[CONTENT]
${PANE_CONTENT}

[CONTEXT PRESSURE]
${CONTEXT_PRESSURE}

[ACTION REQUIRED]
${ACTION_PROMPT}"

# 10. Hybrid mode delivery
TRIGGER="pre_compact"
CONTENT_SOURCE="pane"
debug_log "DELIVERING: mode=$HOOK_MODE session_id=$OPENCLAW_SESSION_ID"

if [ "$HOOK_MODE" = "bidirectional" ]; then
  # Wait for OpenClaw response, return decision:block if provided
  debug_log "DELIVERING: bidirectional, waiting for response..."
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" --json 2>&1 || echo "")
  debug_log "RESPONSE: ${RESPONSE:0:200}"

  write_hook_event_record \
    "$JSONL_FILE" "$HOOK_ENTRY_MS" "$HOOK_SCRIPT_NAME" "$SESSION_NAME" \
    "$AGENT_ID" "$OPENCLAW_SESSION_ID" "$TRIGGER" "$STATE" \
    "$CONTENT_SOURCE" "$WAKE_MESSAGE" "$RESPONSE" "sync_delivered"

  # Parse response for decision injection (future enhancement)
  exit 0
else
  # Async: background call with JSONL logging
  deliver_async_with_logging \
    "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
    "$HOOK_SCRIPT_NAME" "$SESSION_NAME" "$AGENT_ID" \
    "$TRIGGER" "$STATE" "$CONTENT_SOURCE"
  debug_log "DELIVERED (async with JSONL logging)"
  exit 0
fi
