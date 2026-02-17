#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  spawn.sh <agent-name> <workdir> [first-command] [--system-prompt <text-or-file>]

Arguments:
  agent-name     Agent identifier (primary key for registry lookup; also tmux session prefix)
  workdir        Working directory for Claude Code session
  first-command  Optional shell command to run (default: auto-detect from workdir state)

Options:
  --system-prompt <value>   Override system prompt (auto-detects file path vs inline text)

Examples:
  spawn.sh gideon /home/forge/.openclaw/workspace
  spawn.sh warden /home/forge/project "/gsd:resume-work"
  spawn.sh test-agent /tmp/test "claude --dangerously-skip-permissions" --system-prompt "Custom prompt"
  spawn.sh gideon /workspace --system-prompt /path/to/prompt.txt

Behavior:
  - Unknown agents are auto-created in registry with sensible defaults
  - System prompt composition: CLI override > registry agent prompt > default file
  - First command auto-detection: /init, /gsd:resume-work, /gsd:new-project @PRD, or /gsd:help
  - Tmux session name conflicts resolved with -2 suffix
USAGE
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required binary: $1"
}

resolve_skill_root_directory() {
  cd "$(dirname "$0")/.." && pwd
}

ensure_registry_exists() {
  local registry_file_path="$1"
  local registry_directory
  registry_directory="$(dirname "$registry_file_path")"

  mkdir -p "$registry_directory"

  if [ ! -f "$registry_file_path" ]; then
    cat > "$registry_file_path" <<'JSON'
{
  "global_status_openclaw_session_id": "",
  "global_status_openclaw_session_key": "",
  "agents": []
}
JSON
    log "Created recovery registry: ${registry_file_path}"
  fi
}

validate_registry_json() {
  local registry_file_path="$1"

  if ! jq empty "$registry_file_path" >/dev/null 2>&1; then
    local corrupt_backup="${registry_file_path}.corrupt-$(date +%s)"
    mv "$registry_file_path" "$corrupt_backup"
    log "WARN: Corrupt registry backed up to ${corrupt_backup}"

    cat > "$registry_file_path" <<'JSON'
{
  "global_status_openclaw_session_id": "",
  "global_status_openclaw_session_key": "",
  "agents": []
}
JSON
    log "Created fresh registry: ${registry_file_path}"
  fi
}

read_agent_entry_from_registry() {
  local registry_file_path="$1"
  local agent_name="$2"

  jq -c --arg agent_id "$agent_name" \
    '.agents[] | select(.agent_id == $agent_id)' \
    "$registry_file_path" 2>/dev/null || echo ""
}

upsert_agent_entry_in_registry() {
  local registry_file_path="$1"
  local agent_name="$2"
  local working_directory="$3"
  local tmux_session_name="$4"

  local tmp_file="${registry_file_path}.tmp"

  jq --arg agent_id "$agent_name" \
     --arg workdir "$working_directory" \
     --arg session_name "$tmux_session_name" \
     '
  if (.agents | map(.agent_id) | index($agent_id)) then
    .agents |= map(
      if .agent_id == $agent_id then
        . + {
          "working_directory": $workdir,
          "tmux_session_name": $session_name
        }
      else . end
    )
  else
    .agents += [{
      "agent_id": $agent_id,
      "enabled": true,
      "auto_wake": true,
      "topic_id": 1,
      "openclaw_session_id": "",
      "working_directory": $workdir,
      "tmux_session_name": $session_name,
      "claude_resume_target": "",
      "claude_launch_command": "claude --dangerously-skip-permissions",
      "claude_post_launch_mode": "resume_then_agent_pick",
      "system_prompt": "",
      "hook_settings": {}
    }]
  end
' "$registry_file_path" > "$tmp_file"

  mv "$tmp_file" "$registry_file_path"
}

compose_system_prompt() {
  local registry_file_path="$1"
  local agent_name="$2"
  local cli_override_prompt="$3"
  local default_prompt_file_path="$4"

  # Priority 1: CLI override (if provided)
  if [ -n "$cli_override_prompt" ]; then
    echo "$cli_override_prompt"
    return 0
  fi

  # Priority 2: Agent-specific prompt from registry
  local agent_prompt
  agent_prompt=$(jq -r --arg agent_id "$agent_name" \
    '.agents[] | select(.agent_id == $agent_id) | .system_prompt // ""' \
    "$registry_file_path" 2>/dev/null || echo "")

  if [ -n "$agent_prompt" ]; then
    echo "$agent_prompt"
    return 0
  fi

  # Priority 3: Default prompt file
  if [ -f "$default_prompt_file_path" ]; then
    cat "$default_prompt_file_path"
    return 0
  fi

  # Fallback: empty string (no system prompt)
  echo ""
}

is_non_empty_project() {
  local working_directory="$1"

  # Check if git repo with commits
  if [ -d "$working_directory/.git" ] && git -C "$working_directory" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$working_directory" rev-parse --verify HEAD >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Check for any visible files/directories
  if find "$working_directory" -mindepth 1 -maxdepth 1 -not -name '.*' -print -quit | grep -q .; then
    return 0
  fi

  return 1
}

choose_first_cmd() {
  local working_directory="$1"

  local claude_md="${working_directory}/CLAUDE.md"
  local planning_directory="${working_directory}/.planning"
  local prd_file="${working_directory}/PRD.md"

  # Non-empty project without CLAUDE.md -> /init
  if is_non_empty_project "$working_directory" && [ ! -f "$claude_md" ]; then
    echo "/init"
    return 0
  fi

  # Has .planning directory -> /gsd:resume-work
  if [ -d "$planning_directory" ]; then
    echo "/gsd:resume-work"
    return 0
  fi

  # Has PRD.md -> /gsd:new-project @PRD.md
  if [ -f "$prd_file" ]; then
    echo "/gsd:new-project @PRD.md"
    return 0
  fi

  # Default: /gsd:help
  echo "/gsd:help"
}

resolve_tmux_session_name() {
  local base_session_name="$1"
  local session_name="$base_session_name"
  local counter=2

  while tmux has-session -t "$session_name" 2>/dev/null; do
    session_name="${base_session_name}-${counter}"
    counter=$((counter + 1))
  done

  echo "$session_name"
}

start_tmux_server_if_needed() {
  if ! tmux info >/dev/null 2>&1; then
    log "Starting tmux server"
    tmux start-server
  fi
}

log_git_preflight_info() {
  local working_directory="$1"

  if [ -d "$working_directory/.git" ] && git -C "$working_directory" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "git: $(git -C "$working_directory" branch --show-current 2>/dev/null || echo '<detached>')"
    log "git recent:"
    git -C "$working_directory" --no-pager log -n 5 --oneline --decorate 2>/dev/null | sed 's/^/  /' || true
  else
    log "git: (not a git repo)"
  fi
}

main() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  # Positional arguments
  local agent_name="${1:-}"
  local workdir="${2:-}"
  local explicit_first_command="${3:-}"
  shift 3 2>/dev/null || shift $# 2>/dev/null || true

  # Validate required arguments
  [ -n "$agent_name" ] || { usage; die "Missing <agent-name>"; }
  [ -n "$workdir" ] || { usage; die "Missing <workdir>"; }
  [ -d "$workdir" ] || die "workdir does not exist: $workdir"

  # Parse optional flags
  local cli_override_prompt=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --system-prompt)
        local prompt_value="${2:-}"
        [ -n "$prompt_value" ] || die "--system-prompt requires a value"

        # Auto-detect: file path vs inline text
        if [ -f "$prompt_value" ]; then
          cli_override_prompt="$(cat "$prompt_value")"
        else
          cli_override_prompt="$prompt_value"
        fi
        shift 2
        ;;
      *)
        usage
        die "Unknown argument: $1"
        ;;
    esac
  done

  # Startup checks
  require_bin jq
  require_bin tmux
  require_bin git
  require_bin claude

  # Resolve paths
  local skill_root_directory
  skill_root_directory="$(resolve_skill_root_directory)"
  local registry_file_path="${skill_root_directory}/config/recovery-registry.json"
  local default_prompt_file_path="${skill_root_directory}/config/default-system-prompt.txt"

  # Ensure registry exists and is valid JSON
  ensure_registry_exists "$registry_file_path"
  validate_registry_json "$registry_file_path"

  # Read agent entry (if exists)
  local agent_entry
  agent_entry="$(read_agent_entry_from_registry "$registry_file_path" "$agent_name")"

  # Determine working directory (use registry value if agent exists and CLI arg not provided)
  local effective_workdir="$workdir"
  if [ -n "$agent_entry" ]; then
    local registry_workdir
    registry_workdir="$(echo "$agent_entry" | jq -r '.working_directory // ""')"
    if [ -n "$registry_workdir" ] && [ "$workdir" = "$registry_workdir" ]; then
      effective_workdir="$registry_workdir"
    fi
  fi

  # Determine tmux session name
  local base_session_name="${agent_name}-main"
  if [ -n "$agent_entry" ]; then
    base_session_name="$(echo "$agent_entry" | jq -r '.tmux_session_name // ""')"
    [ -n "$base_session_name" ] || base_session_name="${agent_name}-main"
  fi

  local actual_session_name
  actual_session_name="$(resolve_tmux_session_name "$base_session_name")"

  if [ "$actual_session_name" != "$base_session_name" ]; then
    log "Session name conflict resolved: ${base_session_name} -> ${actual_session_name}"
  fi

  # Compose system prompt (CLI override > agent prompt > default file)
  local final_system_prompt
  final_system_prompt="$(compose_system_prompt "$registry_file_path" "$agent_name" "$cli_override_prompt" "$default_prompt_file_path")"

  # Determine first command
  local first_command="$explicit_first_command"
  if [ -z "$first_command" ]; then
    first_command="$(choose_first_cmd "$effective_workdir")"
  fi

  # Log preflight info
  log_git_preflight_info "$effective_workdir"

  # Start tmux server if needed
  start_tmux_server_if_needed

  # Create tmux session
  log "Starting tmux session: ${actual_session_name} (cwd=${effective_workdir})"
  tmux new-session -d -s "$actual_session_name" -c "$effective_workdir"

  # Read Claude launch command from registry (or use default)
  local claude_launch_command="claude --dangerously-skip-permissions"
  if [ -n "$agent_entry" ]; then
    local registry_launch_cmd
    registry_launch_cmd="$(echo "$agent_entry" | jq -r '.claude_launch_command // ""')"
    [ -n "$registry_launch_cmd" ] && claude_launch_command="$registry_launch_cmd"
  fi

  # Build Claude command with system prompt
  local full_claude_command="$claude_launch_command"
  if [ -n "$final_system_prompt" ]; then
    full_claude_command="${claude_launch_command} --append-system-prompt $(printf %q "$final_system_prompt")"
  fi

  # Launch Claude Code in tmux
  log "Launching Claude Code in tmux"
  tmux send-keys -t "${actual_session_name}:0.0" "$full_claude_command" Enter

  # Wait for TUI startup
  sleep 1

  # Send first command
  log "First command => $first_command"
  tmux send-keys -t "${actual_session_name}:0.0" -l -- "$first_command"
  tmux send-keys -t "${actual_session_name}:0.0" Enter

  # Update registry with actual session name
  upsert_agent_entry_in_registry "$registry_file_path" "$agent_name" "$effective_workdir" "$actual_session_name"

  log "Attach: tmux attach -t $actual_session_name"
}

main "$@"
