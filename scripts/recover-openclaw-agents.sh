#!/usr/bin/env bash
set -uo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_directory="$(cd "${script_directory}/.." && pwd)"
default_registry_path="${skill_directory}/config/recovery-registry.json"

function print_usage() {
  cat <<'USAGE'
Usage:
  recover-openclaw-agents.sh [--registry <path>] [--skip-session-id-sync]

Purpose:
  Deterministically recover OpenClaw + Claude Code working agents after reboot/OOM.

Behavior:
  1) Reads agent recovery registry (jq-only, no Python dependency).
  2) Filters agents where enabled=true and auto_wake=true.
  3) Ensures tmux session exists in correct working directory.
  4) Launches Claude Code if missing in that tmux pane.
  5) Passes per-agent system_prompt via --append-system-prompt (fallback to default).
  6) Sends deterministic wake instruction to exact OpenClaw session id.
  7) Sends Telegram notification only on failures (silent on full success).

Requirements:
  - tmux
  - jq
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

function validate_registry_or_recreate() {
  local registry_path="$1"
  local global_status_openclaw_session_id="$2"

  if ! jq empty "${registry_path}" 2>/dev/null; then
    local corrupt_backup="${registry_path}.corrupt-$(date +%s)"
    mv "${registry_path}" "${corrupt_backup}"
    log_info "corrupt registry backed up to: ${corrupt_backup}"

    ensure_registry_file_exists "${registry_path}"
    log_info "created fresh registry skeleton"

    if [[ -n "${global_status_openclaw_session_id}" ]]; then
      local notification_message="Registry file was corrupt and has been backed up to ${corrupt_backup}. Created fresh skeleton. Review backup if recovery state is needed."
      openclaw agent --session-id "${global_status_openclaw_session_id}" --message "${notification_message}" >/dev/null 2>&1 &
      log_info "sent Telegram notification about corrupt registry"
    fi

    return 1
  fi

  return 0
}

function start_tmux_server_if_needed() {
  if ! tmux list-sessions >/dev/null 2>&1; then
    log_info "tmux server not running; starting it"
    tmux start-server || true
  fi
}

function ensure_tmux_session_exists() {
  local tmux_session_name="$1"
  local working_directory="$2"

  if tmux has-session -t "${tmux_session_name}" 2>/dev/null; then
    log_info "tmux session exists: ${tmux_session_name}"
    return 0
  fi

  local final_session_name="${tmux_session_name}"
  local counter=2

  while tmux has-session -t "${final_session_name}" 2>/dev/null; do
    final_session_name="${tmux_session_name}-${counter}"
    counter=$((counter + 1))
  done

  if [[ "${final_session_name}" != "${tmux_session_name}" ]]; then
    log_info "session name conflict; using: ${final_session_name}"
  fi

  log_info "creating tmux session ${final_session_name} in ${working_directory}"
  tmux new-session -d -s "${final_session_name}" -c "${working_directory}" || return 1

  return 0
}

function ensure_claude_is_running_in_tmux() {
  local tmux_session_name="$1"
  local claude_launch_command="$2"
  local system_prompt="$3"

  if ! tmux has-session -t "${tmux_session_name}" 2>/dev/null; then
    log_info "tmux session missing before Claude launch check: ${tmux_session_name}"
    return 1
  fi

  local pane_snapshot
  pane_snapshot="$(tmux capture-pane -pt "${tmux_session_name}:0.0" -S -80 2>/dev/null || true)"

  if grep -Eiq 'Resume Session|Type to Search|/gsd:|What can I help|Claude Code' <<<"${pane_snapshot}"; then
    log_info "Claude-like TUI already detected in ${tmux_session_name}; skipping launch"
    return 0
  fi

  local launch_command_with_prompt="${claude_launch_command}"
  if [[ -n "${system_prompt}" ]]; then
    local escaped_prompt
    escaped_prompt=$(printf %q "${system_prompt}")
    launch_command_with_prompt="${claude_launch_command} --append-system-prompt ${escaped_prompt}"
  fi

  log_info "launching Claude in ${tmux_session_name}"
  tmux send-keys -t "${tmux_session_name}:0.0" "${launch_command_with_prompt}" Enter || return 1
  sleep 2

  local pane_after_launch
  pane_after_launch="$(tmux capture-pane -pt "${tmux_session_name}:0.0" -S -120 2>/dev/null || true)"
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

  local post_launch_command="/resume"
  local expected_pattern='Resume Session|Type to Search|Enter to select'
  if [[ "${claude_post_launch_mode}" == "gsd_resume_work" ]]; then
    post_launch_command="/gsd:resume-work"
    expected_pattern='/gsd:|What can I help|Try "'
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
      pane_snapshot="$(tmux capture-pane -pt "${tmux_session_name}:0.0" -S -120 2>/dev/null || true)"
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

  if [[ "${claude_post_launch_mode}" != "resume_then_agent_pick" ]]; then
    return 0
  fi

  local seconds_waited="0"
  local max_wait_seconds="45"

  while [[ "${seconds_waited}" -lt "${max_wait_seconds}" ]]; do
    local pane_snapshot
    pane_snapshot="$(tmux capture-pane -pt "${tmux_session_name}:0.0" -S -120 2>/dev/null || true)"

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

  openclaw agent \
    --session-id "${openclaw_session_id}" \
    --message "${deterministic_instruction}" >/dev/null 2>&1 || return 1

  log_info "wake instruction sent to OpenClaw session ${openclaw_session_id} (${agent_id})"
  return 0
}

function main() {
  local registry_path="${default_registry_path}"
  local skip_session_id_sync="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --registry)
        registry_path="${2:-}"
        shift 2
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

  require_binary jq
  require_binary tmux
  require_binary openclaw

  log_info "using recovery registry: ${registry_path}"
  ensure_registry_file_exists "${registry_path}"

  local global_status_openclaw_session_id=""
  global_status_openclaw_session_id="$(jq -r '.global_status_openclaw_session_id // ""' "${registry_path}" 2>/dev/null || echo "")"

  validate_registry_or_recreate "${registry_path}" "${global_status_openclaw_session_id}"

  start_tmux_server_if_needed

  if [[ "${skip_session_id_sync}" != "1" ]]; then
    local sync_script_path="${skill_directory}/scripts/sync-recovery-registry-session-ids.sh"
    if [[ -x "${sync_script_path}" ]]; then
      "${sync_script_path}" --registry "${registry_path}" || true
    else
      log_info "session id sync script not executable: ${sync_script_path}"
    fi
  fi

  global_status_openclaw_session_id="$(jq -r '.global_status_openclaw_session_id // ""' "${registry_path}" 2>/dev/null || echo "")"

  local default_system_prompt_file="${skill_directory}/config/default-system-prompt.txt"
  local default_system_prompt=""
  if [[ -f "${default_system_prompt_file}" ]]; then
    default_system_prompt="$(cat "${default_system_prompt_file}")"
  fi

  local restored_agent_count="0"
  local skipped_agent_count="0"
  local failed_agent_count="0"
  local restored_agent_names=()
  local failed_agents=()

  while IFS= read -r agent_entry; do
    local enabled
    local auto_wake
    enabled="$(echo "${agent_entry}" | jq -r '.enabled // false')"
    auto_wake="$(echo "${agent_entry}" | jq -r '.auto_wake // false')"

    if [[ "${enabled}" != "true" || "${auto_wake}" != "true" ]]; then
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
    local agent_system_prompt

    agent_id="$(echo "${agent_entry}" | jq -r '.agent_id // ""')"
    openclaw_session_id="$(echo "${agent_entry}" | jq -r '.openclaw_session_id // ""')"
    working_directory="$(echo "${agent_entry}" | jq -r '.working_directory // ""')"
    tmux_session_name="$(echo "${agent_entry}" | jq -r '.tmux_session_name // ""')"
    topic_id="$(echo "${agent_entry}" | jq -r '.topic_id // ""')"
    claude_resume_target="$(echo "${agent_entry}" | jq -r '.claude_resume_target // ""')"
    claude_launch_command="$(echo "${agent_entry}" | jq -r '.claude_launch_command // "claude --dangerously-skip-permissions"')"
    claude_post_launch_mode="$(echo "${agent_entry}" | jq -r '.claude_post_launch_mode // "resume_then_agent_pick"')"
    agent_system_prompt="$(echo "${agent_entry}" | jq -r '.system_prompt // ""')"

    if [[ -z "${agent_id}" || -z "${openclaw_session_id}" || -z "${working_directory}" || -z "${tmux_session_name}" ]]; then
      log_info "agent entry missing required fields; skipping"
      failed_agent_count="$((failed_agent_count + 1))"
      failed_agents+=("${agent_id:-unknown}: missing required fields (agent_id, openclaw_session_id, working_directory, or tmux_session_name)")
      continue
    fi

    if [[ "${claude_post_launch_mode}" != "resume_then_agent_pick" && "${claude_post_launch_mode}" != "gsd_resume_work" ]]; then
      log_info "invalid claude_post_launch_mode for ${agent_id}: ${claude_post_launch_mode}"
      failed_agent_count="$((failed_agent_count + 1))"
      failed_agents+=("${agent_id}: invalid claude_post_launch_mode (${claude_post_launch_mode})")
      continue
    fi

    if [[ ! -d "${working_directory}" ]]; then
      log_info "working directory missing for ${agent_id}: ${working_directory}"
      failed_agent_count="$((failed_agent_count + 1))"
      failed_agents+=("${agent_id}: working directory missing (${working_directory})")
      continue
    fi

    local final_system_prompt="${default_system_prompt}"
    if [[ -n "${agent_system_prompt}" ]]; then
      final_system_prompt="${agent_system_prompt}"
    fi

    local recovery_failed_for_agent="0"
    local failure_reason=""

    if ! ensure_tmux_session_exists "${tmux_session_name}" "${working_directory}"; then
      log_info "failed to ensure tmux session for ${agent_id}; retrying after 3s"
      sleep 3
      if ! ensure_tmux_session_exists "${tmux_session_name}" "${working_directory}"; then
        recovery_failed_for_agent="1"
        failure_reason="tmux session creation failed (retry exhausted)"
        log_info "failed to ensure tmux session for ${agent_id} after retry"
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      if ! ensure_claude_is_running_in_tmux "${tmux_session_name}" "${claude_launch_command}" "${final_system_prompt}"; then
        log_info "failed to launch or detect Claude in ${tmux_session_name} for ${agent_id}; retrying after 3s"
        sleep 3
        if ! ensure_claude_is_running_in_tmux "${tmux_session_name}" "${claude_launch_command}" "${final_system_prompt}"; then
          recovery_failed_for_agent="1"
          failure_reason="Claude launch not confirmed after retry"
          log_info "failed to launch or detect Claude in ${tmux_session_name} for ${agent_id} after retry"
        fi
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      if ! send_deterministic_claude_post_launch_command "${tmux_session_name}" "${claude_post_launch_mode}"; then
        log_info "failed to send deterministic post-launch command for ${agent_id}; retrying after 3s"
        sleep 3
        if ! send_deterministic_claude_post_launch_command "${tmux_session_name}" "${claude_post_launch_mode}"; then
          recovery_failed_for_agent="1"
          failure_reason="post-launch command failed (retry exhausted)"
          log_info "failed to send deterministic post-launch command for ${agent_id} after retry"
        fi
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      if ! send_recovery_instruction_to_openclaw_session \
        "${openclaw_session_id}" \
        "${agent_id}" \
        "${topic_id}" \
        "${tmux_session_name}" \
        "${claude_resume_target}"; then
        log_info "failed to send recovery instruction to OpenClaw session for ${agent_id}; retrying after 3s"
        sleep 3
        if ! send_recovery_instruction_to_openclaw_session \
          "${openclaw_session_id}" \
          "${agent_id}" \
          "${topic_id}" \
          "${tmux_session_name}" \
          "${claude_resume_target}"; then
          recovery_failed_for_agent="1"
          failure_reason="OpenClaw wake instruction failed (retry exhausted)"
          log_info "failed to send recovery instruction to OpenClaw session for ${agent_id} after retry"
        fi
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      if ! wait_for_agent_resume_and_apply_fallback_if_stuck \
        "${tmux_session_name}" \
        "${claude_post_launch_mode}"; then
        log_info "failed while waiting for resume progress for ${agent_id}"
        recovery_failed_for_agent="1"
        failure_reason="resume progress wait failed"
      fi
    fi

    if [[ "${recovery_failed_for_agent}" == "0" ]]; then
      restored_agent_count="$((restored_agent_count + 1))"
      restored_agent_names+=("${agent_id}")
    else
      failed_agent_count="$((failed_agent_count + 1))"
      failed_agents+=("${agent_id}: ${failure_reason}")
      log_info "failed to recover ${agent_id}: ${failure_reason}"
    fi
  done < <(jq -c '.agents[]' "${registry_path}" 2>/dev/null || echo "")

  local restored_agents_joined="none"
  if [[ ${#restored_agent_names[@]} -gt 0 ]]; then
    restored_agents_joined="$(IFS=', '; echo "${restored_agent_names[*]}")"
  fi

  local summary_message
  summary_message="Deterministic recovery summary: restored=${restored_agent_count}, skipped=${skipped_agent_count}, failed=${failed_agent_count}. Restored agents: ${restored_agents_joined}."

  log_info "${summary_message}"

  if [[ "${failed_agent_count}" -gt 0 ]]; then
    local failure_details
    failure_details="Recovery failures:\n"
    for failure in "${failed_agents[@]}"; do
      failure_details+="- ${failure}\n"
    done

    if [[ -n "${global_status_openclaw_session_id}" ]]; then
      openclaw agent --session-id "${global_status_openclaw_session_id}" --message "${failure_details}" >/dev/null 2>&1 &
      log_info "sent Telegram notification about recovery failures"
    fi
  fi
}

main "$@"
