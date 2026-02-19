#!/usr/bin/env bash
set -euo pipefail

# register-all-hooks-logger.sh — Register the hook-event-logger.sh for ALL 15 Claude Code hook events.
# Additive: preserves all existing GSD hooks, appends logger entries alongside them.
# Also clears all existing log files in logs/ to provide a clean slate.
# Usage: bash scripts/register-all-hooks-logger.sh

# ============================================================================
# Logging
# ============================================================================

log_message() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

# ============================================================================
# Constants
# ============================================================================

SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
LOGGER_SCRIPT="${SKILL_ROOT}/scripts/hook-event-logger.sh"

log_message "Starting hook-event-logger registration for all 15 events"
log_message "Skill root: $SKILL_ROOT"
log_message "Settings file: $SETTINGS_FILE"
log_message "Logger script: $LOGGER_SCRIPT"

# ============================================================================
# Pre-flight Checks
# ============================================================================

if ! command -v jq &> /dev/null; then
  log_message "ERROR: jq is not installed. Install jq to continue."
  exit 1
fi

log_message "jq found: $(command -v jq)"

if [ ! -f "$LOGGER_SCRIPT" ]; then
  log_message "ERROR: Logger script not found: $LOGGER_SCRIPT"
  log_message "Run Task 1 first to create hook-event-logger.sh"
  exit 1
fi

log_message "Logger script verified: $LOGGER_SCRIPT"

if [ ! -f "$SETTINGS_FILE" ]; then
  log_message "WARNING: $SETTINGS_FILE not found. Creating minimal configuration."
  echo '{}' > "$SETTINGS_FILE"
fi

# ============================================================================
# Part A: Clear Existing Log Files
# ============================================================================

log_message ""
log_message "===== Clearing Log Files ====="

SKILL_LOG_DIR="${SKILL_ROOT}/logs"
mkdir -p "$SKILL_LOG_DIR"

# Remove all log and lock files (silent if none exist)
rm -f "${SKILL_LOG_DIR}/"*.log "${SKILL_LOG_DIR}/"*.jsonl \
      "${SKILL_LOG_DIR}/"*.lock "${SKILL_LOG_DIR}/"*.txt 2>/dev/null || true

log_message "Cleared all files in $SKILL_LOG_DIR"

# ============================================================================
# Part B: Backup Settings
# ============================================================================

BACKUP_FILE="${SETTINGS_FILE}.backup-$(date +%s)"
cp "$SETTINGS_FILE" "$BACKUP_FILE"
log_message "Created backup: $BACKUP_FILE"

# ============================================================================
# Part C: Build Logger Rule and Register All 15 Events
# ============================================================================

log_message ""
log_message "===== Registering Logger for All 15 Hook Events ====="

# Build the single logger rule entry (catch-all, no matcher)
LOGGER_RULE=$(jq -cn --arg command "$LOGGER_SCRIPT" '{
  "hooks": [
    {
      "type": "command",
      "command": $command,
      "timeout": 10
    }
  ]
}')

# Build Notification logger entries — catch-all plus four subtype matchers
NOTIFICATION_LOGGER_CATCHALL=$(jq -cn --arg command "$LOGGER_SCRIPT" '{
  "hooks": [
    {
      "type": "command",
      "command": $command,
      "timeout": 10
    }
  ]
}')

NOTIFICATION_LOGGER_AUTH=$(jq -cn --arg command "$LOGGER_SCRIPT" '{
  "matcher": "auth_success",
  "hooks": [
    {
      "type": "command",
      "command": $command,
      "timeout": 10
    }
  ]
}')

NOTIFICATION_LOGGER_PERMISSION=$(jq -cn --arg command "$LOGGER_SCRIPT" '{
  "matcher": "permission_prompt",
  "hooks": [
    {
      "type": "command",
      "command": $command,
      "timeout": 10
    }
  ]
}')

NOTIFICATION_LOGGER_IDLE=$(jq -cn --arg command "$LOGGER_SCRIPT" '{
  "matcher": "idle_prompt",
  "hooks": [
    {
      "type": "command",
      "command": $command,
      "timeout": 10
    }
  ]
}')

NOTIFICATION_LOGGER_ELICITATION=$(jq -cn --arg command "$LOGGER_SCRIPT" '{
  "matcher": "elicitation_dialog",
  "hooks": [
    {
      "type": "command",
      "command": $command,
      "timeout": 10
    }
  ]
}')

log_message "Built logger rule: $LOGGER_SCRIPT"

# Single jq invocation: append logger to ALL 15 events, preserving existing entries.
# Events with existing GSD hooks: Stop, Notification, SessionEnd, PreCompact, PreToolUse, PostToolUse, SessionStart
# Events with no prior GSD hooks: Setup, UserPromptSubmit, PermissionRequest, PostToolUseFailure,
#   SubagentStart, SubagentStop, TeammateIdle, TaskCompleted
jq \
  --argjson logger_rule "$LOGGER_RULE" \
  --argjson notification_catchall "$NOTIFICATION_LOGGER_CATCHALL" \
  --argjson notification_auth "$NOTIFICATION_LOGGER_AUTH" \
  --argjson notification_permission "$NOTIFICATION_LOGGER_PERMISSION" \
  --argjson notification_idle "$NOTIFICATION_LOGGER_IDLE" \
  --argjson notification_elicitation "$NOTIFICATION_LOGGER_ELICITATION" \
'
  # Ensure hooks object exists
  .hooks = (.hooks // {}) |

  # 1. SessionStart — append logger (existing: gsd-check-update.js)
  .hooks.SessionStart = ((.hooks.SessionStart // []) + [$logger_rule]) |

  # 2. Setup — new logger entry (no prior GSD hook)
  .hooks.Setup = ((.hooks.Setup // []) + [$logger_rule]) |

  # 3. UserPromptSubmit — new logger entry (no prior GSD hook)
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [$logger_rule]) |

  # 4. PreToolUse — append catch-all logger (existing: AskUserQuestion matcher)
  .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$logger_rule]) |

  # 5. PermissionRequest — new logger entry (no prior GSD hook)
  .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) + [$logger_rule]) |

  # 6. PostToolUse — append catch-all logger (existing: AskUserQuestion matcher)
  .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [$logger_rule]) |

  # 7. PostToolUseFailure — new logger entry (no prior GSD hook)
  .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) + [$logger_rule]) |

  # 8. Notification — append all four subtype matchers + catch-all alongside existing GSD hooks
  .hooks.Notification = ((.hooks.Notification // []) + [
    $notification_auth,
    $notification_permission,
    $notification_idle,
    $notification_elicitation,
    $notification_catchall
  ]) |

  # 9. SubagentStart — new logger entry (no prior GSD hook)
  .hooks.SubagentStart = ((.hooks.SubagentStart // []) + [$logger_rule]) |

  # 10. SubagentStop — new logger entry (no prior GSD hook)
  .hooks.SubagentStop = ((.hooks.SubagentStop // []) + [$logger_rule]) |

  # 11. Stop — append logger (existing: stop-hook.sh)
  .hooks.Stop = ((.hooks.Stop // []) + [$logger_rule]) |

  # 12. TeammateIdle — new logger entry (no prior GSD hook)
  .hooks.TeammateIdle = ((.hooks.TeammateIdle // []) + [$logger_rule]) |

  # 13. TaskCompleted — new logger entry (no prior GSD hook)
  .hooks.TaskCompleted = ((.hooks.TaskCompleted // []) + [$logger_rule]) |

  # 14. PreCompact — append logger (existing: pre-compact-hook.sh)
  .hooks.PreCompact = ((.hooks.PreCompact // []) + [$logger_rule]) |

  # 15. SessionEnd — append logger (existing: session-end-hook.sh)
  .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [$logger_rule])
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
# Verification Summary
# ============================================================================

log_message ""
log_message "===== Hook Registration Verification Summary ====="
log_message ""

ALL_15_EVENTS=(
  SessionStart Setup UserPromptSubmit PreToolUse PermissionRequest
  PostToolUse PostToolUseFailure Notification SubagentStart SubagentStop
  Stop TeammateIdle TaskCompleted PreCompact SessionEnd
)

TOTAL_EVENTS_REGISTERED=0
TOTAL_LOGGER_ENTRIES=0

for event_name in "${ALL_15_EVENTS[@]}"; do
  event_count=$(jq --arg event "$event_name" '.hooks[$event] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
  logger_count=$(jq --arg event "$event_name" --arg logger "$LOGGER_SCRIPT" \
    '[.hooks[$event][] | select(.hooks[]?.command == $logger)] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
  gsd_count=$((event_count - logger_count))

  if [ "$event_count" -gt 0 ]; then
    TOTAL_EVENTS_REGISTERED=$((TOTAL_EVENTS_REGISTERED + 1))
    TOTAL_LOGGER_ENTRIES=$((TOTAL_LOGGER_ENTRIES + logger_count))
    log_message "  $event_name: $event_count entries (GSD: $gsd_count, logger: $logger_count)"
  else
    log_message "  $event_name: WARNING - no entries found!"
  fi
done

log_message ""
log_message "Events registered: $TOTAL_EVENTS_REGISTERED / 15"
log_message "Logger entries added: $TOTAL_LOGGER_ENTRIES"
log_message ""

# Verify additive: existing GSD Stop hook is still present
STOP_GSD_PRESENT=$(jq -r '.hooks.Stop[] | select(.hooks[]?.command | contains("stop-hook.sh")) | .hooks[].command' "$SETTINGS_FILE" 2>/dev/null || echo "")
if [ -n "$STOP_GSD_PRESENT" ]; then
  log_message "Additive proof — Stop (GSD): $STOP_GSD_PRESENT"
else
  log_message "WARNING: Stop GSD hook (stop-hook.sh) not found!"
fi

STOP_LOGGER_PRESENT=$(jq -r '.hooks.Stop[] | select(.hooks[]?.command | contains("hook-event-logger.sh")) | .hooks[].command' "$SETTINGS_FILE" 2>/dev/null || echo "")
if [ -n "$STOP_LOGGER_PRESENT" ]; then
  log_message "Additive proof — Stop (logger): $STOP_LOGGER_PRESENT"
else
  log_message "WARNING: Stop logger hook not found!"
fi

log_message ""
log_message "====================================="
log_message ""
log_message "Hook-event-logger registered for all 15 events in ~/.claude/settings.json"
log_message "Backup saved to: $BACKUP_FILE"
log_message ""
log_message "Logs cleared. Ready for warden-main-4 session to trigger events."
log_message "Inspect logs in: $SKILL_LOG_DIR"
log_message ""
log_message "IMPORTANT: Restart all Claude Code sessions to activate new hooks."
