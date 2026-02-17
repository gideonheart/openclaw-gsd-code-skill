#!/usr/bin/env bash
set -euo pipefail

# PreCompact hook: Capture pane state before Claude Code compacts context window.
# Sends full wake message with pane content, context pressure, and available actions.
# Supports hybrid mode (async or bidirectional).

# 1. Consume stdin immediately to prevent pipe blocking
STDIN_JSON=$(cat)

# 2. Guard: Exit if not in tmux environment
[ -z "${TMUX:-}" ] && exit 0

# 3. Extract tmux session name
SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
[ -z "$SESSION_NAME" ] && exit 0

# 4. Registry lookup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_PATH="${SCRIPT_DIR}/../config/recovery-registry.json"

# Exit if registry doesn't exist
[ ! -f "$REGISTRY_PATH" ] && exit 0

# Query agent data matching session name
AGENT_DATA=$(jq --arg session "$SESSION_NAME" \
  '.agents[] | select(.tmux_session_name == $session)' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")

# Exit if no matching agent (non-managed session)
[ -z "$AGENT_DATA" ] && exit 0

# Extract required fields
AGENT_ID=$(echo "$AGENT_DATA" | jq -r '.agent_id')
OPENCLAW_SESSION_ID=$(echo "$AGENT_DATA" | jq -r '.openclaw_session_id')

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
if [ "$HOOK_MODE" = "bidirectional" ]; then
  # Wait for OpenClaw response, return decision:block if provided
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" --json 2>/dev/null || echo "")
  # Parse response for decision injection (future enhancement)
  exit 0
else
  # Async: background call, exit immediately
  openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >/dev/null 2>&1 &
  exit 0
fi
