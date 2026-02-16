#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_directory="$(cd "${script_directory}/.." && pwd)"
default_registry_path="${skill_directory}/config/recovery-registry.json"

function print_usage() {
  cat <<'USAGE'
Usage:
  recover-openclaw-agents.sh [--registry <path>] [--dry-run] [--skip-session-id-sync]

Purpose:
  Deterministically recover OpenClaw + Claude Code working agents after reboot/OOM.

Behavior:
  1) Reads agent recovery registry.
  2) Filters agents where enabled=true and auto_wake=true.
  3) Ensures tmux session exists in correct working directory.
  4) Launches Claude Code if missing in that tmux pane.
  5) Sends deterministic wake instruction to exact OpenClaw session id.
  6) Sends one global status summary to configured global status session.

Requirements:
  - tmux
  - python3
  - openclaw CLI
USAGE
}

function log_info() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

function fail_with_error() {
  log_info "ERROR: $*"
  exit 1
}

function require_binary() {
  local binary_name="$1"
  command -v "${binary_name}" >/dev/null 2>&1 || fail_with_error "Required binary not found: ${binary_name}"
}

function ensure_registry_file_exists() {
  local registry_path="$1"

  if [[ -f "${registry_path}" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${registry_path}")"
  cat > "${registry_path}" <<'JSON'
{
  "global_status_openclaw_session_id": "",
  "global_status_openclaw_session_key": "",
  "agents": []
}
JSON
  log_info "created missing empty registry: ${registry_path}"
}

function parse_registry_to_json_lines() {
  local registry_path="$1"
  python3 - "$registry_path" <<'PYTHON'
import json
import pathlib
import sys

registry_path = pathlib.Path(sys.argv[1])
if not registry_path.exists():
    raise SystemExit(f"registry file not found: {registry_path}")

registry = json.loads(registry_path.read_text())
if not isinstance(registry, dict):
    raise SystemExit("registry root must be an object")

global_status_openclaw_session_id = registry.get("global_status_openclaw_session_id", "")
agents = registry.get("agents")
if not isinstance(agents, list):
    raise SystemExit("registry.agents must be an array")

print(json.dumps({
    "type": "global",
    "global_status_openclaw_session_id": global_status_openclaw_session_id,
}))

for index, agent in enumerate(agents):
    if not isinstance(agent, dict):
        raise SystemExit(f"agents[{index}] must be an object")

    enabled = bool(agent.get("enabled", False))
    auto_wake = bool(agent.get("auto_wake", False))

    if enabled and auto_wake and not agent.get("topic_id"):
        raise SystemExit(
            f"agents[{index}] has auto_wake=true; topic_id is required"
        )

    print(json.dumps({
        "type": "agent",
        "agent_index": index,
        "agent": agent,
    }))
PYTHON
}

function ensure_tmux_session_exists() {
  local tmux_session_name="$1"
  local working_directory="$2"
  local dry_run_enabled="$3"

  if tmux has-session -t "${tmux_session_name}" 2>/dev/null; then
    log_info "tmux session exists: ${tmux_session_name}"
    echo "exists"
    return 0
  fi

  if [[ "${dry_run_enabled}" == "1" ]]; then
    log_info "DRY RUN: would create tmux session ${tmux_session_name} in ${working_directory}"
    echo "created"
    return 0
  fi

  log_info "creating tmux session ${tmux_session_name} in ${working_directory}"
  tmux new-session -d -s "${tmux_session_name}" -c "${working_directory}"
  echo "created"
}

function ensure_claude_is_running_in_tmux() {
  local tmux_session_name="$1"
  local claude_launch_command="$2"
  local dry_run_enabled="$3"

  if ! tmux has-session -t "${tmux_session_name}" 2>/dev/null; then
    if [[ "${dry_run_enabled}" == "1" ]]; then
      log_info "DRY RUN: tmux session ${tmux_session_name} not present yet; skipping Claude process check"
      return 0
    fi
    fail_with_error "tmux session missing before Claude launch check: ${tmux_session_name}"
  fi

  local pane_snapshot
  pane_snapshot="$(tmux capture-pane -pt "${tmux_session_name}:0.0" -S -80 || true)"

  if grep -Eiq 'Resume Session|Type to Search|/gsd:|What can I help|Claude Code' <<<"${pane_snapshot}"; then
    log_info "Claude-like TUI already detected in ${tmux_session_name}; skipping launch"
    return 0
  fi

  if [[ "${dry_run_enabled}" == "1" ]]; then
    log_info "DRY RUN: would launch Claude in ${tmux_session_name} with: ${claude_launch_command}"
    return 0
  fi

  log_info "launching Claude in ${tmux_session_name}"
  tmux send-keys -t "${tmux_session_name}:0.0" "${claude_launch_command}" Enter
  sleep 2

  local pane_after_launch
  pane_after_launch="$(tmux capture-pane -pt "${tmux_session_name}:0.0" -S -120 || true)"
  if grep -Eiq 'Resume Session|Type to Search|/gsd:|What can I help|Claude Code' <<<"${pane_after_launch}"; then
    log_info "Claude launch confirmed in ${tmux_session_name}"
    return 0
  fi

  log_info "Claude launch not confirmed in ${tmux_session_name}; pane tail follows:"
  printf '%s\n' "${pane_after_launch}" | tail -n 12 | sed 's/^/[pane] /'
  return 1
}

function send_deterministic_claude_post_launch_command() {
  local tmux_session_name="$1"
  local claude_post_launch_mode="$2"
  local dry_run_enabled="$3"

  local post_launch_command="/resume"
  local expected_pattern='Resume Session|Type to Search|Enter to select'
  if [[ "${claude_post_launch_mode}" == "gsd_resume_work" ]]; then
    post_launch_command="/gsd:resume-work"
    expected_pattern='/gsd:|What can I help|Try "'
  fi

  if [[ "${dry_run_enabled}" == "1" ]]; then
    log_info "DRY RUN: would send deterministic post-launch command in ${tmux_session_name}: ${post_launch_command}"
    return 0
  fi

  local attempt="1"
  local max_attempts="2"
  while [[ "${attempt}" -le "${max_attempts}" ]]; do
    tmux send-keys -t "${tmux_session_name}:0.0" C-u
    tmux send-keys -t "${tmux_session_name}:0.0" -l -- "${post_launch_command}"
    tmux send-keys -t "${tmux_session_name}:0.0" Enter
    log_info "sent deterministic post-launch command in ${tmux_session_name}: ${post_launch_command} (attempt ${attempt}/${max_attempts})"

    local waited="0"
    while [[ "${waited}" -lt "10" ]]; do
      local pane_snapshot
      pane_snapshot="$(tmux capture-pane -pt "${tmux_session_name}:0.0" -S -120 || true)"
      if grep -Eiq "${expected_pattern}" <<<"${pane_snapshot}"; then
        return 0
      fi
      sleep 1
      waited="$((waited + 1))"
    done

    attempt="$((attempt + 1))"
  done

  log_info "post-launch command did not produce expected UI in ${tmux_session_name}: ${post_launch_command}"
  return 1
}

function wait_for_agent_resume_and_apply_fallback_if_stuck() {
  local tmux_session_name="$1"
  local claude_post_launch_mode="$2"
  local dry_run_enabled="$3"

  if [[ "${claude_post_launch_mode}" != "resume_then_agent_pick" ]]; then
    return 0
  fi

  if [[ "${dry_run_enabled}" == "1" ]]; then
    log_info "DRY RUN: would wait for resume selection progress and apply fallback if stuck in ${tmux_session_name}"
    return 0
  fi

  local seconds_waited="0"
  local max_wait_seconds="45"

  while [[ "${seconds_waited}" -lt "${max_wait_seconds}" ]]; do
    local pane_snapshot
    pane_snapshot="$(tmux capture-pane -pt "${tmux_session_name}:0.0" -S -120 || true)"

    if ! grep -Eiq 'Resume Session|Type to Search|Enter to select' <<<"${pane_snapshot}"; then
      log_info "resume menu cleared in ${tmux_session_name}; continuing"
      return 0
    fi

    sleep 1
    seconds_waited="$((seconds_waited + 1))"
  done

  log_info "resume menu still visible after ${max_wait_seconds}s in ${tmux_session_name}; applying fallback /gsd:resume-work"
  tmux send-keys -t "${tmux_session_name}:0.0" C-u
  tmux send-keys -t "${tmux_session_name}:0.0" -l -- "/gsd:resume-work"
  tmux send-keys -t "${tmux_session_name}:0.0" Enter
  return 0
}

function send_recovery_instruction_to_openclaw_session() {
  local openclaw_session_id="$1"
  local agent_id="$2"
  local topic_id="$3"
  local tmux_session_name="$4"
  local claude_resume_target="$5"
  local dry_run_enabled="$6"

  local menu_driver_script_path="${skill_directory}/scripts/menu-driver.sh"

  local deterministic_instruction
  deterministic_instruction="Recovery mode for agent ${agent_id}.\n"
  deterministic_instruction+="Context: recovered after reboot/OOM. Topic id: ${topic_id}.\n"
  deterministic_instruction+="Use tmux session: ${tmux_session_name}.\n"
  deterministic_instruction+="Step 1: run '${menu_driver_script_path} ${tmux_session_name} snapshot' and inspect current TUI state.\n"
  deterministic_instruction+="Step 2: if Resume Session menu is visible, pick the correct session.\n"
  if [[ -n "${claude_resume_target}" ]]; then
    deterministic_instruction+="Preferred resume target: ${claude_resume_target}.\n"
  fi
  deterministic_instruction+="Step 3: wait until resumed session is loaded, then read last GSD response and decide next command.\n"
  deterministic_instruction+="Step 4: if resume cannot be completed, execute fallback '/gsd:resume-work'.\n"
  deterministic_instruction+="Step 5: send one concise status update in topic ${topic_id}: restored session + next action."

  if [[ "${dry_run_enabled}" == "1" ]]; then
    log_info "DRY RUN: would wake OpenClaw session ${openclaw_session_id} for agent ${agent_id}"
    return 0
  fi

  openclaw agent \
    --session-id "${openclaw_session_id}" \
    --message "${deterministic_instruction}" >/dev/null

  log_info "wake instruction sent to OpenClaw session ${openclaw_session_id} (${agent_id})"
}

function send_global_summary() {
  local global_status_openclaw_session_id="$1"
  local summary_message="$2"
  local dry_run_enabled="$3"

  if [[ -z "${global_status_openclaw_session_id}" ]]; then
    log_info "global_status_openclaw_session_id not configured; skipping global summary"
    return 0
  fi

  if [[ "${dry_run_enabled}" == "1" ]]; then
    log_info "DRY RUN: would send global summary to ${global_status_openclaw_session_id}"
    return 0
  fi

  openclaw agent \
    --session-id "${global_status_openclaw_session_id}" \
    --message "${summary_message}" >/dev/null

  log_info "global summary sent to ${global_status_openclaw_session_id}"
}

function main() {
  local registry_path="${default_registry_path}"
  local dry_run_enabled="0"
  local skip_session_id_sync="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --registry)
        registry_path="${2:-}"
        shift 2
        ;;
      --dry-run)
        dry_run_enabled="1"
        shift
        ;;
      --skip-session-id-sync)
        skip_session_id_sync="1"
        shift
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        fail_with_error "Unknown argument: $1"
        ;;
    esac
  done

  require_binary tmux
  require_binary python3
  require_binary openclaw

  log_info "using recovery registry: ${registry_path}"
  ensure_registry_file_exists "${registry_path}"

  if [[ "${skip_session_id_sync}" != "1" ]]; then
    local sync_script_path="${skill_directory}/scripts/sync-recovery-registry-session-ids.sh"
    if [[ -x "${sync_script_path}" ]]; then
      if [[ "${dry_run_enabled}" == "1" ]]; then
        "${sync_script_path}" --registry "${registry_path}" --dry-run || true
      else
        "${sync_script_path}" --registry "${registry_path}" || true
      fi
    else
      log_info "session id sync script not executable: ${sync_script_path}"
    fi
  fi

  local global_status_openclaw_session_id=""
  local restored_agent_count="0"
  local skipped_agent_count="0"
  local failed_agent_count="0"
  local restored_agent_names=()

  while IFS= read -r registry_line; do
    local line_type
    line_type="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["type"])' "${registry_line}")"

    if [[ "${line_type}" == "global" ]]; then
      global_status_openclaw_session_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("global_status_openclaw_session_id", ""))' "${registry_line}")"
      continue
    fi

    local enabled
    local auto_wake
    enabled="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1])["agent"].get("enabled", False) else "0")' "${registry_line}")"
    auto_wake="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1])["agent"].get("auto_wake", False) else "0")' "${registry_line}")"

    if [[ "${enabled}" != "1" || "${auto_wake}" != "1" ]]; then
      skipped_agent_count="$((skipped_agent_count + 1))"
      continue
    fi

    local agent_id
    local openclaw_session_id
    local working_directory
    local tmux_session_name
    local topic_id
    local claude_resume_target
    local claude_launch_command
    local claude_post_launch_mode

    agent_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agent"].get("agent_id", ""))' "${registry_line}")"
    openclaw_session_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agent"].get("openclaw_session_id", ""))' "${registry_line}")"
    working_directory="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agent"].get("working_directory", ""))' "${registry_line}")"
    tmux_session_name="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agent"].get("tmux_session_name", ""))' "${registry_line}")"
    topic_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agent"].get("topic_id", ""))' "${registry_line}")"
    claude_resume_target="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agent"].get("claude_resume_target", ""))' "${registry_line}")"
    claude_launch_command="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agent"].get("claude_launch_command", "claude --dangerously-skip-permissions"))' "${registry_line}")"
    claude_post_launch_mode="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agent"].get("claude_post_launch_mode", "resume_then_agent_pick"))' "${registry_line}")"

    if [[ -z "${agent_id}" || -z "${openclaw_session_id}" || -z "${working_directory}" || -z "${tmux_session_name}" ]]; then
      log_info "agent entry missing required fields; skipping"
      failed_agent_count="$((failed_agent_count + 1))"
      continue
    fi

    if [[ "${claude_post_launch_mode}" != "resume_then_agent_pick" && "${claude_post_launch_mode}" != "gsd_resume_work" ]]; then
      log_info "invalid claude_post_launch_mode for ${agent_id}: ${claude_post_launch_mode}"
      failed_agent_count="$((failed_agent_count + 1))"
      continue
    fi

    if [[ ! -d "${working_directory}" ]]; then
      log_info "working directory missing for ${agent_id}: ${working_directory}"
      failed_agent_count="$((failed_agent_count + 1))"
      continue
    fi

    local recovery_failed_for_agent="0"

    if ! ensure_tmux_session_exists "${tmux_session_name}" "${working_directory}" "${dry_run_enabled}" >/dev/null; then
      recovery_failed_for_agent="1"
      log_info "failed to ensure tmux session for ${agent_id}"
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      if ! ensure_claude_is_running_in_tmux "${tmux_session_name}" "${claude_launch_command}" "${dry_run_enabled}"; then
        recovery_failed_for_agent="1"
        log_info "failed to launch or detect Claude in ${tmux_session_name} for ${agent_id}"
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      if ! send_deterministic_claude_post_launch_command "${tmux_session_name}" "${claude_post_launch_mode}" "${dry_run_enabled}"; then
        recovery_failed_for_agent="1"
        log_info "failed to send deterministic post-launch command for ${agent_id}"
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      if ! send_recovery_instruction_to_openclaw_session \
        "${openclaw_session_id}" \
        "${agent_id}" \
        "${topic_id}" \
        "${tmux_session_name}" \
        "${claude_resume_target}" \
        "${dry_run_enabled}"; then
        recovery_failed_for_agent="1"
        log_info "failed to send recovery instruction to OpenClaw session for ${agent_id}"
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      if ! wait_for_agent_resume_and_apply_fallback_if_stuck \
        "${tmux_session_name}" \
        "${claude_post_launch_mode}" \
        "${dry_run_enabled}"; then
        recovery_failed_for_agent="1"
        log_info "failed while waiting for resume progress for ${agent_id}"
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      restored_agent_count="$((restored_agent_count + 1))"
      restored_agent_names+=("${agent_id}")
    else
      failed_agent_count="$((failed_agent_count + 1))"
      log_info "failed to recover ${agent_id}"
    fi
  done < <(parse_registry_to_json_lines "${registry_path}")

  local restored_agents_joined="none"
  if [[ ${#restored_agent_names[@]} -gt 0 ]]; then
    restored_agents_joined="$(IFS=', '; echo "${restored_agent_names[*]}")"
  fi

  local summary_message
  summary_message="Deterministic recovery summary: restored=${restored_agent_count}, skipped=${skipped_agent_count}, failed=${failed_agent_count}. Restored agents: ${restored_agents_joined}."

  log_info "${summary_message}"
  send_global_summary "${global_status_openclaw_session_id}" "${summary_message}" "${dry_run_enabled}"
}

main "$@"
