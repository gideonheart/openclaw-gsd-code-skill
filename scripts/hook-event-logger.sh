#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/hook-preamble.sh"

# hook-event-logger.sh — Universal debug logger for all 15 Claude Code hook events.
# Reads raw stdin JSON payload and writes it to per-session log files for analysis.
# This script does NOT do registry lookup, wake delivery, or session state detection.
# It is purely a raw event logger for debugging and hook payload inspection.

# Safety trap: ensure Claude Code is never crashed by logger errors
trap 'exit 0' ERR

# 1. Consume all stdin immediately (before anything else)
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)

# 2. Extract event name from payload
EVENT_NAME=$(printf '%s' "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")
STDIN_BYTE_COUNT=${#STDIN_JSON}

# 3. Log to global hooks.log via debug_log (GSD_HOOK_LOG defaults to hooks.log from preamble)
debug_log "EVENT=$EVENT_NAME bytes=$STDIN_BYTE_COUNT"

# 4. Detect tmux session name — fall back to "no-tmux" if not in tmux
SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
if [ -z "$SESSION_NAME" ]; then
  SESSION_NAME="no-tmux"
fi

# 5. Redirect GSD_HOOK_LOG to per-session file (same pattern as existing hooks)
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"

# 6. Log structured entry to per-session .log file
{
  printf '[%s] ===== HOOK EVENT: %s =====\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$EVENT_NAME"
  printf '[%s] timestamp: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf '[%s] session: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$SESSION_NAME"
  printf '[%s] stdin_bytes: %d\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$STDIN_BYTE_COUNT"
  printf '[%s] payload:\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf '%s' "$STDIN_JSON" | jq '.' 2>/dev/null || printf '%s' "$STDIN_JSON"
  printf '[%s] ===== END EVENT: %s =====\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$EVENT_NAME"
} >> "$GSD_HOOK_LOG" 2>/dev/null || true

debug_log "logged event=$EVENT_NAME to ${SESSION_NAME}.log"

# 7. Append compact JSONL line to per-session raw events file (atomic via flock)
RAW_EVENTS_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}-raw-events.jsonl"
JSONL_LOCK_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}-raw-events.lock"

# Build JSONL record — handle invalid JSON gracefully
TIMESTAMP_ISO=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
if printf '%s' "$STDIN_JSON" | jq empty 2>/dev/null; then
  # Valid JSON: use --argjson for structured payload
  JSONL_RECORD=$(jq -cn \
    --arg event "$EVENT_NAME" \
    --arg timestamp "$TIMESTAMP_ISO" \
    --arg session "$SESSION_NAME" \
    --argjson payload "$STDIN_JSON" \
    '{timestamp: $timestamp, event: $event, session: $session, payload: $payload}' 2>/dev/null || echo "")
else
  # Invalid JSON: store raw stdin as string
  JSONL_RECORD=$(jq -cn \
    --arg event "$EVENT_NAME" \
    --arg timestamp "$TIMESTAMP_ISO" \
    --arg session "$SESSION_NAME" \
    --arg payload "$STDIN_JSON" \
    '{timestamp: $timestamp, event: $event, session: $session, payload: $payload}' 2>/dev/null || echo "")
fi

# Atomic append via flock if record was built successfully
if [ -n "$JSONL_RECORD" ]; then
  (
    flock -x 9
    printf '%s\n' "$JSONL_RECORD" >> "$RAW_EVENTS_FILE"
  ) 9>"$JSONL_LOCK_FILE" 2>/dev/null || true
fi

debug_log "appended to ${SESSION_NAME}-raw-events.jsonl"

exit 0
