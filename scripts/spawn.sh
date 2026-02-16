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
  spawn.sh <session-name> <workdir> [--prd <path>] [--autoresponder] [--agent-id <id>] [--topic-id <n>] [--auto-wake <true|false>]

Arguments:
  session-name   tmux session name (use warden-/gideon- prefix if you want Warden dashboard discovery)
  workdir        directory to start Claude Code in

Options:
  --prd <path>                 PRD file path relative to workdir OR absolute (default: PRD.md if exists)
  --autoresponder              Enable local GSD menu responder helper loop (off by default)
  --agent-id <id>              Agent id for recovery registry upsert (default: derived from session-name prefix before first '-')
  --topic-id <n>               Topic id to store in recovery registry (default: 1)
  --auto-wake <true|false>     Auto wake value for recovery registry entry (default: true)

Behavior (first command selection):
  - If repo is non-empty and CLAUDE.md missing -> /init
  - Else if .planning/ exists -> /gsd:resume-work
  - Else if PRD exists -> /gsd:new-project @<PRD>
  - Else -> /gsd:help

USAGE
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required binary: $1"
}

derive_agent_id_from_session_name() {
  local session_name="$1"
  local derived_agent_id="${session_name%%-*}"
  if [ -z "$derived_agent_id" ] || [ "$derived_agent_id" = "$session_name" ]; then
    echo "$session_name"
  else
    echo "$derived_agent_id"
  fi
}

upsert_recovery_registry_entry() {
  local agent_id="$1"
  local topic_id="$2"
  local auto_wake_value="$3"
  local working_directory="$4"
  local tmux_session_name="$5"

  local skill_root_directory
  skill_root_directory="$(cd "$(dirname "$0")/.." && pwd)"
  local registry_file_path="${skill_root_directory}/config/recovery-registry.json"

  mkdir -p "${skill_root_directory}/config"
  if [ ! -f "${registry_file_path}" ]; then
    cat > "${registry_file_path}" <<'JSON'
{
  "global_status_openclaw_session_id": "",
  "global_status_openclaw_session_key": "",
  "agents": []
}
JSON
    log "Created recovery registry: ${registry_file_path}"
  fi

  python3 - "${registry_file_path}" "${agent_id}" "${topic_id}" "${auto_wake_value}" "${working_directory}" "${tmux_session_name}" <<'PYTHON'
import json
import pathlib
import re
import sys

registry_file_path = pathlib.Path(sys.argv[1])
agent_id = sys.argv[2]
topic_id = int(sys.argv[3])
auto_wake_value = sys.argv[4].lower() == "true"
working_directory = sys.argv[5]
tmux_session_name = sys.argv[6]

registry = json.loads(registry_file_path.read_text())
if not isinstance(registry, dict):
    registry = {}

registry.setdefault("global_status_openclaw_session_id", "")
registry.setdefault("global_status_openclaw_session_key", "")
registry.setdefault("agents", [])

if not isinstance(registry["agents"], list):
    registry["agents"] = []

sessions_index_path = pathlib.Path(f"/home/forge/.openclaw/agents/{agent_id}/sessions/sessions.json")
selected_session_id = ""
selected_key = ""
selected_updated_at = -1
if sessions_index_path.exists():
    try:
        sessions_index = json.loads(sessions_index_path.read_text())
        if isinstance(sessions_index, dict):
            pattern = re.compile(rf"^agent:{re.escape(agent_id)}:openai:")
            for session_key, session_record in sessions_index.items():
                if not pattern.match(session_key):
                    continue
                if not isinstance(session_record, dict):
                    continue
                session_id = session_record.get("sessionId")
                updated_at = session_record.get("updatedAt")
                if not session_id or not isinstance(updated_at, (int, float)):
                    continue
                if int(updated_at) > selected_updated_at:
                    selected_updated_at = int(updated_at)
                    selected_session_id = str(session_id)
                    selected_key = session_key
    except Exception:
        pass

matching_entry = None
for entry in registry["agents"]:
    if isinstance(entry, dict) and entry.get("agent_id") == agent_id:
        matching_entry = entry
        break

if matching_entry is None:
    matching_entry = {"agent_id": agent_id}
    registry["agents"].append(matching_entry)

matching_entry["enabled"] = True
matching_entry["auto_wake"] = auto_wake_value
matching_entry["topic_id"] = topic_id
matching_entry["working_directory"] = working_directory
matching_entry["tmux_session_name"] = tmux_session_name
matching_entry.setdefault("claude_resume_target", "")
matching_entry.setdefault("claude_launch_command", "claude --dangerously-skip-permissions")
matching_entry.setdefault("claude_post_launch_mode", "resume_then_agent_pick")
if selected_session_id:
    matching_entry["openclaw_session_id"] = selected_session_id
else:
    matching_entry.setdefault("openclaw_session_id", "")

registry_file_path.write_text(json.dumps(registry, indent=2) + "\n")

print(f"RECOVERY_REGISTRY_UPSERT agent={agent_id} openclaw_session_id={matching_entry.get('openclaw_session_id','')} source={selected_key or '<none>'}")
PYTHON
}

is_non_empty_project() {
  # "Non-empty" heuristic:
  # - any git commit exists OR
  # - there is at least one non-dot file/dir in the top-level
  local wd="$1"
  if [ -d "$wd/.git" ] && git -C "$wd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$wd" rev-parse --verify HEAD >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Fallback: any visible entry
  if find "$wd" -mindepth 1 -maxdepth 1 -not -name '.*' -print -quit | grep -q .; then
    return 0
  fi

  return 1
}

choose_first_cmd() {
  local wd="$1"
  local prd="$2"

  local claude_md="$wd/CLAUDE.md"
  local planning_dir="$wd/.planning"

  if is_non_empty_project "$wd" && [ ! -f "$claude_md" ]; then
    echo "/init"
    return 0
  fi

  if [ -d "$planning_dir" ]; then
    echo "/gsd:resume-work"
    return 0
  fi

  if [ -n "$prd" ]; then
    # keep @ relative if possible
    local prd_display="$prd"
    if [[ "$prd" = "$wd"/* ]]; then
      prd_display="${prd#"$wd"/}"
    fi
    echo "/gsd:new-project @${prd_display}"
    return 0
  fi

  echo "/gsd:help"
}

strict_prompt() {
  cat <<'PROMPT'
STRICT OUTPUT MODE:
You MUST output ONLY a single slash-command per message.
Use /gsd:* commands from https://github.com/gsd-build/get-shit-done exclusively for all work.
You MAY output non-gsd slash commands only when required to operate the session (allowed: /init, /clear, /resume, /resume-work, /pause-work).
ABSOLUTELY NO other text, explanations, bash commands, or code blocks.
If uncertain, output /gsd:help.
PROMPT
}

main() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  local session_name="${1:-}"
  local workdir="${2:-}"
  shift 2 || true

  [ -n "$session_name" ] || { usage; die "Missing <session-name>"; }
  [ -n "$workdir" ] || { usage; die "Missing <workdir>"; }
  [ -d "$workdir" ] || die "workdir does not exist: $workdir"

  require_bin tmux
  require_bin git
  require_bin claude

  local prd_path=""
  local enable_autoresponder="0"
  local configured_agent_id=""
  local configured_topic_id="1"
  local configured_auto_wake="true"
  while [ $# -gt 0 ]; do
    case "$1" in
      --prd)
        prd_path="${2:-}"; shift 2 || true
        ;;
      --autoresponder)
        enable_autoresponder="1"; shift
        ;;
      --agent-id)
        configured_agent_id="${2:-}"; shift 2 || true
        ;;
      --topic-id)
        configured_topic_id="${2:-}"; shift 2 || true
        ;;
      --auto-wake)
        configured_auto_wake="${2:-}"; shift 2 || true
        ;;
      *)
        usage
        die "Unknown arg: $1"
        ;;
    esac
  done

  [[ "$configured_topic_id" =~ ^[0-9]+$ ]] || die "--topic-id must be numeric"
  [[ "$configured_auto_wake" =~ ^(true|false)$ ]] || die "--auto-wake must be true or false"

  # Resolve PRD
  if [ -z "$prd_path" ]; then
    if [ -f "$workdir/PRD.md" ]; then
      prd_path="$workdir/PRD.md"
    fi
  else
    if [[ "$prd_path" != /* ]]; then
      prd_path="$workdir/$prd_path"
    fi
    [ -f "$prd_path" ] || die "PRD file not found: $prd_path"
  fi

  local first_cmd
  first_cmd="$(choose_first_cmd "$workdir" "$prd_path")"

  # Preflight info (deterministic)
  if [ -d "$workdir/.git" ] && git -C "$workdir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "git: $(git -C "$workdir" branch --show-current 2>/dev/null || true)"
    log "git recent:"
    git -C "$workdir" --no-pager log -n 5 --oneline --decorate 2>/dev/null | sed 's/^/  /' || true
  else
    log "git: (not a git repo)"
  fi

  # Start tmux session
  if tmux has-session -t "$session_name" 2>/dev/null; then
    die "tmux session already exists: $session_name"
  fi

  log "Starting tmux session: $session_name (cwd=$workdir)"
  tmux new-session -d -s "$session_name" -c "$workdir"

  # Build claude command with strict prompt.
  # Use printf %q to safely escape the prompt for shell.
  local sp
  sp="$(strict_prompt)"

  # We pass the prompt as a single argument by shell-quoting it.
  # shellcheck disable=SC2086
  local claude_cmd
  claude_cmd="claude --dangerously-skip-permissions --append-system-prompt $(printf %q "$sp")"

  log "Launching Claude Code in tmux"
  tmux send-keys -t "$session_name:0.0" "$claude_cmd" Enter

  # Give the TUI a moment to come up
  sleep 1

  log "First command => $first_cmd"
  tmux send-keys -t "$session_name:0.0" -l -- "$first_cmd"
  tmux send-keys -t "$session_name:0.0" Enter

  if [ "$enable_autoresponder" = "1" ]; then
    local responder="$PWD/skills/gsd-code-skill/scripts/autoresponder.sh"
    if [ ! -x "$responder" ]; then
      responder="$(cd "$(dirname "$0")" && pwd)/autoresponder.sh"
    fi
    if [ -x "$responder" ]; then
      log "Starting local autoresponder hook for session: $session_name"
      nohup "$responder" "$session_name" >/tmp/gsd-autoresponder-${session_name}.log 2>&1 &
    else
      log "WARN: autoresponder script not found/executable: $responder"
    fi
  fi

  local effective_agent_id="$configured_agent_id"
  if [ -z "$effective_agent_id" ]; then
    effective_agent_id="$(derive_agent_id_from_session_name "$session_name")"
  fi

  upsert_recovery_registry_entry \
    "$effective_agent_id" \
    "$configured_topic_id" \
    "$configured_auto_wake" \
    "$workdir" \
    "$session_name"

  log "Attach: tmux attach -t $session_name"
}

main "$@"
