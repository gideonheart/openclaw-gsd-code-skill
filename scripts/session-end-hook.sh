#!/usr/bin/env bash
set -euo pipefail

# SessionEnd hook: Notify OpenClaw when Claude Code session terminates.
# Sends minimal wake message (identity + trigger only, no pane capture).
# Exit cleanly in <5ms for non-managed sessions.

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
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >/dev/null 2>&1 &

exit 0
