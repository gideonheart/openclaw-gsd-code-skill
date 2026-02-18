#!/usr/bin/env bash
set -euo pipefail

# register-hooks.sh - Idempotent hook registration script for Claude Code
# Registers all 7 hook events (Stop, Notification idle, Notification permission, SessionEnd, PreCompact, PreToolUse, PostToolUse) in ~/.claude/settings.json and removes gsd-session-hook.sh from SessionStart
# Usage: bash scripts/register-hooks.sh

# ============================================================================
# Logging
# ============================================================================

log_message() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

# ============================================================================
# Constants
# ============================================================================

SETTINGS_FILE="$HOME/.claude/settings.json"
SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log_message "Starting hook registration"
log_message "Skill root: $SKILL_ROOT"
log_message "Settings file: $SETTINGS_FILE"

# ============================================================================
# Pre-flight Checks
# ============================================================================

# Check jq is installed
if ! command -v jq &> /dev/null; then
  log_message "ERROR: jq is not installed. Install jq to continue."
  exit 1
fi

log_message "jq found: $(command -v jq)"

# Check settings.json exists, create minimal {} if not
if [ ! -f "$SETTINGS_FILE" ]; then
  log_message "WARNING: $SETTINGS_FILE not found. Creating minimal configuration."
  echo '{}' > "$SETTINGS_FILE"
fi

# Verify all hook scripts exist
HOOK_SCRIPTS=(
  "stop-hook.sh"
  "notification-idle-hook.sh"
  "notification-permission-hook.sh"
  "session-end-hook.sh"
  "pre-compact-hook.sh"
  "pre-tool-use-hook.sh"
  "post-tool-use-hook.sh"
)

for script in "${HOOK_SCRIPTS[@]}"; do
  script_path="$SKILL_ROOT/scripts/$script"
  if [ ! -f "$script_path" ]; then
    log_message "ERROR: Hook script not found: $script_path"
    exit 1
  fi
  log_message "Verified hook script: $script"
done

# ============================================================================
# Backup
# ============================================================================

BACKUP_FILE="${SETTINGS_FILE}.backup-$(date +%s)"
cp "$SETTINGS_FILE" "$BACKUP_FILE"
log_message "Created backup: $BACKUP_FILE"

# ============================================================================
# Build Hooks Configuration
# ============================================================================

# Build the complete hooks configuration as a JSON string
# All paths are absolute, constructed from $SKILL_ROOT/scripts/
HOOKS_CONFIG=$(cat <<EOF
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/stop-hook.sh",
          "timeout": 600
        }
      ]
    }
  ],
  "Notification": [
    {
      "matcher": "idle_prompt",
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/notification-idle-hook.sh",
          "timeout": 600
        }
      ]
    },
    {
      "matcher": "permission_prompt",
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/notification-permission-hook.sh",
          "timeout": 600
        }
      ]
    }
  ],
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/session-end-hook.sh"
        }
      ]
    }
  ],
  "PreCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/pre-compact-hook.sh",
          "timeout": 600
        }
      ]
    }
  ],
  "PreToolUse": [
    {
      "matcher": "AskUserQuestion",
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/pre-tool-use-hook.sh",
          "timeout": 10
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "AskUserQuestion",
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/post-tool-use-hook.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
EOF
)

log_message "Built hooks configuration"

# ============================================================================
# Merge with jq
# ============================================================================

log_message "Merging hooks into settings.json"

jq --argjson new "$HOOKS_CONFIG" '
  # Ensure hooks object exists
  .hooks = (.hooks // {}) |

  # Replace target hook events
  .hooks.Stop = $new.Stop |
  .hooks.Notification = $new.Notification |
  .hooks.SessionEnd = $new.SessionEnd |
  .hooks.PreCompact = $new.PreCompact |
  .hooks.PreToolUse = $new.PreToolUse |
  .hooks.PostToolUse = $new.PostToolUse |

  # Clean up SessionStart: remove gsd-session-hook.sh, keep others
  .hooks.SessionStart = (
    if .hooks.SessionStart then
      [.hooks.SessionStart[] | .hooks |= map(select(.command | contains("gsd-session-hook.sh") | not))]
    else
      []
    end
  )
' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"

# ============================================================================
# Validate JSON
# ============================================================================

log_message "Validating generated JSON"

if ! jq empty "${SETTINGS_FILE}.tmp" 2>/dev/null; then
  log_message "ERROR: Generated invalid JSON. Settings unchanged."
  rm "${SETTINGS_FILE}.tmp"
  exit 1
fi

log_message "JSON validation passed"

# ============================================================================
# Atomic Replace
# ============================================================================

mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
log_message "Settings file updated atomically"

# ============================================================================
# Verification Output
# ============================================================================

log_message ""
log_message "===== Hook Registration Summary ====="
log_message ""

# Stop hook
STOP_HOOK=$(jq -r '.hooks.Stop[0]?.hooks[0]?.command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "Stop hook: $STOP_HOOK"

# Notification hooks
NOTIFICATION_IDLE=$(jq -r '.hooks.Notification[] | select(.matcher == "idle_prompt") | .hooks[0].command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "Notification (idle_prompt): $NOTIFICATION_IDLE"

NOTIFICATION_PERMISSION=$(jq -r '.hooks.Notification[] | select(.matcher == "permission_prompt") | .hooks[0].command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "Notification (permission_prompt): $NOTIFICATION_PERMISSION"

# SessionEnd hook
SESSION_END=$(jq -r '.hooks.SessionEnd[0]?.hooks[0]?.command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "SessionEnd hook: $SESSION_END"

# PreCompact hook
PRE_COMPACT=$(jq -r '.hooks.PreCompact[0]?.hooks[0]?.command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "PreCompact hook: $PRE_COMPACT"

# PreToolUse hook (AskUserQuestion)
PRE_TOOL_USE=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[0].command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "PreToolUse (AskUserQuestion): $PRE_TOOL_USE"

# PostToolUse hook (AskUserQuestion)
POST_TOOL_USE=$(jq -r '.hooks.PostToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[0].command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "PostToolUse (AskUserQuestion): $POST_TOOL_USE"

log_message ""

# Check SessionStart hooks
log_message "SessionStart hooks (gsd-session-hook.sh should NOT be present):"
SESSION_START_HOOKS=$(jq -r '.hooks.SessionStart[].hooks[].command // "NONE"' "$SETTINGS_FILE")
if [ -z "$SESSION_START_HOOKS" ]; then
  log_message "  (No SessionStart hooks registered)"
else
  echo "$SESSION_START_HOOKS" | while read -r hook; do
    log_message "  - $hook"
  done
fi

# Verify gsd-session-hook.sh is NOT present
if echo "$SESSION_START_HOOKS" | grep -q "gsd-session-hook.sh"; then
  log_message "WARNING: gsd-session-hook.sh still present in SessionStart hooks!"
else
  log_message "Confirmed: gsd-session-hook.sh removed from SessionStart"
fi

log_message ""
log_message "====================================="
log_message ""
log_message "Hooks successfully registered in ~/.claude/settings.json"
log_message "Backup saved to: $BACKUP_FILE"
log_message ""
log_message "IMPORTANT: Restart all Claude Code sessions to activate new hooks."
log_message "Existing sessions will continue using old configuration until restarted."
