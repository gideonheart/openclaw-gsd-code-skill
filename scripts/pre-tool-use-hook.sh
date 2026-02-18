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

# pre-tool-use-hook.sh - Claude Code PreToolUse hook for AskUserQuestion forwarding
# Fires when Claude calls AskUserQuestion (matcher-scoped in settings.json).
# Extracts structured question data, formats it, and forwards to OpenClaw agent asynchronously.
# CRITICAL: Always exits 0. Never blocks or denies AskUserQuestion. Notification-only.

# ============================================================================
# 1. CONSUME STDIN IMMEDIATELY (prevent pipe blocking)
# ============================================================================
STDIN_JSON=$(cat)
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
debug_log "=== log redirected to per-session file ==="

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
   {agent_id, openclaw_session_id}' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")

if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  debug_log "EXIT: no agent matched tmux_session_name=$SESSION_NAME in registry"
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
# 5. EXTRACT tool_input FROM STDIN JSON
# ============================================================================
TOOL_INPUT=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_input // ""' 2>/dev/null || echo "")
if [ -z "$TOOL_INPUT" ] || [ "$TOOL_INPUT" = "null" ]; then
  debug_log "EXIT: no tool_input in stdin"
  exit 0
fi
debug_log "tool_input_length=${#TOOL_INPUT}"

# ============================================================================
# 6. SOURCE SHARED LIBRARY AND FORMAT QUESTIONS
# ============================================================================
LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
  debug_log "sourced lib/hook-utils.sh"
else
  debug_log "ERROR: could not source lib/hook-utils.sh at $LIB_PATH"
  exit 0
fi

FORMATTED_QUESTIONS=$(format_ask_user_questions "$TOOL_INPUT")
debug_log "formatted_questions_length=${#FORMATTED_QUESTIONS}"

# ============================================================================
# 7. BUILD STRUCTURED WAKE MESSAGE (v2 AskUserQuestion format)
# ============================================================================
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: ask_user_question

[ASK USER QUESTION]
${FORMATTED_QUESTIONS}

[STATE HINT]
state: awaiting_user_input

[AVAILABLE ACTIONS]
menu-driver.sh ${SESSION_NAME} choose <n>
menu-driver.sh ${SESSION_NAME} type <text>
menu-driver.sh ${SESSION_NAME} clear_then <command>
menu-driver.sh ${SESSION_NAME} enter
menu-driver.sh ${SESSION_NAME} esc
menu-driver.sh ${SESSION_NAME} submit
menu-driver.sh ${SESSION_NAME} snapshot"

# ============================================================================
# 8. ASYNC DELIVERY (ALWAYS background, ALWAYS exit 0)
# ============================================================================
# CRITICAL: openclaw call MUST be backgrounded — foreground blocks TUI before
# AskUserQuestion renders (200ms-2s delay)
# CRITICAL: ALWAYS exit 0 — non-zero exit or JSON output to stdout blocks
# AskUserQuestion and the TUI never shows the question
# CRITICAL: Do NOT echo any JSON to stdout — this hook is notification-only
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" \
  >> "$GSD_HOOK_LOG" 2>&1 &
debug_log "DELIVERED (async AskUserQuestion forward, bg PID=$!)"
exit 0
