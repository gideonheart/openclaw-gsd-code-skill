#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/hook-preamble.sh"

# post-tool-use-hook.sh - Claude Code PostToolUse hook for AskUserQuestion answer logging
# Fires when Claude's AskUserQuestion tool completes (after the user submits an answer).
# Extracts the selected answer and tool_use_id, emits a JSONL record linking the answer
# back to the originating PreToolUse record via shared tool_use_id.
# Logs raw stdin for empirical validation of tool_response schema (ASK-05 requirement).
# CRITICAL: Always exits 0. PostToolUse fires after the tool ran — cannot block. Notification-only.

# ============================================================================
# 1. CONSUME STDIN IMMEDIATELY (prevent pipe blocking)
# ============================================================================
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
# Log raw stdin for empirical validation of tool_response schema (ASK-05 requirement).
# This is intentionally verbose during Phase 10; field names can be narrowed once
# the actual tool_response structure for AskUserQuestion is confirmed from a live session.
debug_log "raw_stdin: $(printf '%s' "$STDIN_JSON" | jq -c '.' 2>/dev/null || echo "$STDIN_JSON")"
debug_log "stdin: ${#STDIN_JSON} bytes, hook_event_name=$(printf '%s' "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"

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
# 5. EXTRACT tool_use_id AND answer FROM STDIN JSON
# ============================================================================
TOOL_USE_ID=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_use_id // ""' 2>/dev/null || echo "")
debug_log "tool_use_id=$TOOL_USE_ID"

# Defensive multi-shape extractor — handles both object and string tool_response.
# AskUserQuestion tool_response schema is MEDIUM confidence pending empirical validation.
# The raw_stdin log above provides the data needed to finalize this extractor.
ANSWER_SELECTED=$(printf '%s' "$STDIN_JSON" | \
  jq -r '.tool_response | if type == "object" then (.content // .text // (. | tostring)) elif type == "string" then . else "" end' \
  2>/dev/null || echo "")
debug_log "tool_use_id_length=${#TOOL_USE_ID} answer_selected_length=${#ANSWER_SELECTED}"

# ============================================================================
# 6. BUILD STRUCTURED WAKE MESSAGE (PostToolUse answer notification format)
# ============================================================================
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: ask_user_question_answered

[ANSWER SELECTED]
tool_use_id: ${TOOL_USE_ID}
answer: ${ANSWER_SELECTED}

[STATE HINT]
state: answer_submitted"

# ============================================================================
# 7. ASYNC DELIVERY (ALWAYS background, ALWAYS exit 0)
# ============================================================================
# PostToolUse fires AFTER the tool ran — cannot block AskUserQuestion.
# No bidirectional branch needed. Always async, always exit 0.
TRIGGER="ask_user_question_answered"
STATE="answer_submitted"
CONTENT_SOURCE="tool_response"
EXTRA_FIELDS_JSON=$(jq -cn \
  --arg tool_use_id "$TOOL_USE_ID" \
  --arg answer_selected "$ANSWER_SELECTED" \
  '{"tool_use_id": $tool_use_id, "answer_selected": $answer_selected}')
deliver_async_with_logging \
  "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
  "$HOOK_SCRIPT_NAME" "$SESSION_NAME" "$AGENT_ID" \
  "$TRIGGER" "$STATE" "$CONTENT_SOURCE" \
  "$EXTRA_FIELDS_JSON"
debug_log "DELIVERED (async PostToolUse AskUserQuestion answer with JSONL logging)"
exit 0
