#!/usr/bin/env bash
set -euo pipefail

# bin/hook-event-logger.sh — Universal debug logger for all 15 Claude Code hook events.
# Reads raw stdin JSON payload and writes it to per-session JSONL files for analysis.
# This script does NOT do registry lookup, wake delivery, or session state detection.
# It is purely a raw event logger for debugging and hook payload inspection.

# Self-contained bootstrapping
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_LOG_DIR="${SKILL_ROOT}/logs"
mkdir -p "$SKILL_LOG_DIR" 2>/dev/null || true

SCRIPT_NAME="hook-event-logger.sh"

debug_log() {
  printf '[%s] [%s] %s\n' "$TIMESTAMP_ISO" "$SCRIPT_NAME" "$*" \
    >> "${SKILL_LOG_DIR}/hooks.log" 2>/dev/null || true
}

# 1. Consume all stdin immediately (before anything else)
STDIN_JSON=$(cat)

# Safety trap: from here forward, logger errors must never crash Claude Code
trap 'exit 0' ERR

# 2. Extract event name and session_id from payload
EVENT_NAME=$(printf '%s' "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")
SESSION_ID=$(printf '%s' "$STDIN_JSON" | jq -r '.session_id // ""' 2>/dev/null || echo "")
STDIN_BYTE_COUNT=${#STDIN_JSON}

# 3. Compute timestamp once — reused in all logging and JSONL record
TIMESTAMP_ISO=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# 4. Log to global hooks.log
debug_log "EVENT=$EVENT_NAME bytes=$STDIN_BYTE_COUNT session_id=$SESSION_ID"

# 5. Build unique log prefix from tmux session name + Claude session_id
#    This guarantees separate log files per Claude Code instance, even when
#    multiple instances share the same tmux session or run outside tmux.
TMUX_SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
SHORT_SESSION_ID="${SESSION_ID:0:8}"

if [ -n "$TMUX_SESSION_NAME" ] && [ -n "$SHORT_SESSION_ID" ]; then
  LOG_FILE_PREFIX="${TMUX_SESSION_NAME}-${SHORT_SESSION_ID}"
elif [ -n "$TMUX_SESSION_NAME" ]; then
  LOG_FILE_PREFIX="${TMUX_SESSION_NAME}"
elif [ -n "$SHORT_SESSION_ID" ]; then
  LOG_FILE_PREFIX="session-${SHORT_SESSION_ID}"
else
  LOG_FILE_PREFIX="unknown-session"
fi

# 6. Append compact JSONL line to per-session raw events file
RAW_EVENTS_FILE="${SKILL_LOG_DIR}/${LOG_FILE_PREFIX}-raw-events.jsonl"

# Build JSONL record — handle invalid JSON gracefully
if printf '%s' "$STDIN_JSON" | jq empty 2>/dev/null; then
  PAYLOAD_FLAG="--argjson"
else
  PAYLOAD_FLAG="--arg"
fi

JSONL_RECORD=$(jq -cn \
  --arg event "$EVENT_NAME" \
  --arg timestamp "$TIMESTAMP_ISO" \
  --arg session "$LOG_FILE_PREFIX" \
  $PAYLOAD_FLAG payload "$STDIN_JSON" \
  '{timestamp: $timestamp, event: $event, session: $session, payload: $payload}' 2>/dev/null || echo "")

# Direct append — no locking needed since each session writes to its own file
if [ -n "$JSONL_RECORD" ]; then
  printf '%s\n' "$JSONL_RECORD" >> "$RAW_EVENTS_FILE" 2>/dev/null || true
fi

debug_log "appended to ${LOG_FILE_PREFIX}-raw-events.jsonl"

exit 0
