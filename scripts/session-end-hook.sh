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

# SessionEnd hook: Notify OpenClaw when Claude Code session terminates.
# Sends minimal wake message (identity + trigger only, no pane capture).
# Exit cleanly in <5ms for non-managed sessions.

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

# 5. Build minimal wake message (HOOK-09)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: session_end

[STATE HINT]
state: terminated"

# 6. Deliver notification (always async)
# SessionEnd is always async -- session is terminating, bidirectional mode is meaningless
debug_log "DELIVERING: mode=async (always) session_id=$OPENCLAW_SESSION_ID"
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >> "$GSD_HOOK_LOG" 2>&1 &
debug_log "DELIVERED (async, bg PID=$!)"

# 7. Clean up pane state files for THIS session only
# Only this session's files — other sessions may still be running
# rm -f: silent if files don't exist (pane diff fallback may never have triggered)
rm -f "${SKILL_LOG_DIR}/gsd-pane-prev-${SESSION_NAME}.txt"
rm -f "${SKILL_LOG_DIR}/gsd-pane-lock-${SESSION_NAME}"
debug_log "Cleaned up pane state files for session=$SESSION_NAME"

exit 0
