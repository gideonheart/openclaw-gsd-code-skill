#!/usr/bin/env bash
# lib/hook-utils.sh - Shared utility functions for GSD hook scripts
# Sourced by all hook scripts (registry lookup, extraction, formatting).
# Contains ONLY function definitions - no side effects on source.
# No set -euo pipefail here - the caller sets shell options.

# ==========================================================================
# lookup_agent_in_registry
# ==========================================================================
# Looks up an agent in the recovery registry using prefix matching on
# agent_id. This is resilient to tmux session suffix increments (e.g.,
# warden-main -> warden-main-2 -> warden-main-3) because it matches any
# session name starting with "{agent_id}-" rather than requiring an exact
# tmux_session_name match.
#
# Arguments:
#   $1 - registry_path: path to recovery-registry.json
#   $2 - session_name: current tmux session name
# Returns:
#   Agent JSON on stdout: {agent_id, openclaw_session_id, hook_settings}
#   Empty string if no match or file missing.
# ==========================================================================
lookup_agent_in_registry() {
  local registry_path="$1"
  local session_name="$2"

  if [ -z "$registry_path" ] || [ ! -f "$registry_path" ]; then
    printf ''
    return
  fi

  jq -r \
    --arg session "$session_name" \
    '.agents[] | . as $agent |
     select($session | startswith($agent.agent_id + "-")) |
     {agent_id, openclaw_session_id, hook_settings}' \
    "$registry_path" 2>/dev/null || printf ''
}

# ==========================================================================
# extract_last_assistant_response
# ==========================================================================
# Extracts the last assistant text response from a Claude Code transcript
# JSONL file. Uses tail -40 for constant-time reads (avoids full-file scan).
# Type-filters content blocks to handle thinking/tool_use blocks correctly.
#
# Arguments:
#   $1 - transcript_path: path to the JSONL transcript file
# Returns:
#   Extracted text on stdout (may be empty if extraction fails)
# ==========================================================================
extract_last_assistant_response() {
  local transcript_path="$1"

  if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    printf ''
    return
  fi

  # tail -40: constant-time read of last 40 JSONL lines
  # jq: type-filter for assistant messages, then text content blocks
  # CRITICAL: select(.type == "text") NOT content[0].text — positional
  #   indexing fails when thinking/tool_use blocks precede the text block
  # CRITICAL: 2>/dev/null on both — transcript may have partial JSON line
  #   if Claude Code is mid-write; suppress errors, empty triggers fallback
  tail -40 "$transcript_path" 2>/dev/null | \
    jq -r 'select(.type == "assistant") |
      (.message.content // [])[] |
      select(.type == "text") | .text' 2>/dev/null | \
    tail -1
}

# ==========================================================================
# extract_pane_diff
# ==========================================================================
# Computes a line-level diff of the current pane content against the
# previously stored pane state for this session. Sends only new/added lines.
# Uses flock for concurrent access protection on per-session state files.
#
# Arguments:
#   $1 - session_name: tmux session name (used for state file naming)
#   $2 - current_pane: string of current pane content
# Returns:
#   Pane delta (new lines only) on stdout. On first fire (no previous state),
#   returns last 10 lines of current pane as a baseline.
# ==========================================================================
extract_pane_diff() {
  local session_name="$1"
  local current_pane="$2"
  # SKILL_LOG_DIR is set by the calling hook script before sourcing this library
  local log_directory="${SKILL_LOG_DIR:-/tmp}"
  local previous_file="${log_directory}/gsd-pane-prev-${session_name}.txt"
  local lock_file="${log_directory}/gsd-pane-lock-${session_name}"

  local pane_delta
  pane_delta=$(
    {
      flock -x -w 2 200 || { printf ''; exit 0; }

      if [ -f "$previous_file" ]; then
        diff \
          --new-line-format='%L' \
          --old-line-format='' \
          --unchanged-line-format='' \
          "$previous_file" \
          <(printf '%s\n' "$current_pane") 2>/dev/null || true
      fi

      printf '%s\n' "$current_pane" > "$previous_file" 2>/dev/null || true
    } 200>"$lock_file"
  )

  # If no delta (first fire — no previous file, or content unchanged),
  # fall back to last 10 lines of current pane as baseline
  if [ -z "$pane_delta" ]; then
    pane_delta=$(printf '%s\n' "$current_pane" | tail -10)
  fi

  printf '%s' "$pane_delta"
}

# ==========================================================================
# format_ask_user_questions
# ==========================================================================
# Formats the structured AskUserQuestion tool_input JSON into readable text
# for inclusion in wake messages. Handles questions, headers, multiSelect
# flags, and numbered options with labels and descriptions.
#
# Arguments:
#   $1 - tool_input_json: JSON string of AskUserQuestion tool_input
# Returns:
#   Formatted question text on stdout. On parse error, returns fallback text.
# ==========================================================================
format_ask_user_questions() {
  local tool_input_json="$1"

  printf '%s' "$tool_input_json" | jq -r '
    .questions[] |
    "Question: \(.question)" +
    (if .header then "\nHeader: \(.header)" else "" end) +
    (if .multiSelect then "\nMulti-select: yes" else "\nMulti-select: no" end) +
    "\nOptions:" +
    (.options // [] | to_entries | map(
      "\n  \(.key + 1). \(.value.label)" +
      (if .value.description and .value.description != "" then ": \(.value.description)" else "" end)
    ) | join("")) +
    "\n"
  ' 2>/dev/null || printf '%s' "(could not parse questions)"
}

# ==========================================================================
# write_hook_event_record
# ==========================================================================
# Builds a complete JSONL record from explicit parameters and appends it
# atomically to the per-session .jsonl log file. This is the single write
# point for ALL structured JSONL records across all 6 hook scripts.
#
# All string fields use jq --arg for safe escaping (newlines, quotes, ANSI
# codes, embedded JSON). The duration_ms field uses --argjson for integer
# type. Append uses flock for atomic writes under concurrent hook fires.
#
# Silent failure: jq construction error returns 0, flock timeout returns 0.
# This function NEVER crashes the calling hook.
#
# Arguments (12 explicit positional parameters + 1 optional):
#   $1  - jsonl_file:           path to per-session .jsonl log file
#   $2  - hook_entry_ms:        millisecond timestamp from hook start
#   $3  - hook_script:          basename of calling hook script
#   $4  - session_name:         tmux session name
#   $5  - agent_id:             agent identifier from registry
#   $6  - openclaw_session_id:  OpenClaw session ID from registry
#   $7  - trigger:              event trigger type
#   $8  - state:                detected state
#   $9  - content_source:       how content was obtained
#   $10 - wake_message:         full wake message body
#   $11 - response:             OpenClaw response text
#   $12 - outcome:              delivery result
#   $13 - extra_fields_json:    (optional) JSON object string to merge into record, e.g. '{"questions_forwarded":"..."}'
# Returns:
#   Nothing on stdout. Appends one JSONL line to jsonl_file.
# ==========================================================================
write_hook_event_record() {
  local jsonl_file="$1"
  local hook_entry_ms="$2"
  local hook_script="$3"
  local session_name="$4"
  local agent_id="$5"
  local openclaw_session_id="$6"
  local trigger="$7"
  local state="$8"
  local content_source="$9"
  local wake_message="${10}"
  local response="${11}"
  local outcome="${12}"
  local extra_fields_json="${13:-}"

  local hook_exit_ms
  hook_exit_ms=$(date +%s%3N)
  local duration_ms=$((hook_exit_ms - hook_entry_ms))

  local extra_args=()
  local extra_merge=""
  if [ -n "$extra_fields_json" ]; then
    extra_args=(--argjson extra_fields "$extra_fields_json")
    extra_merge='+ $extra_fields'
  fi

  local record
  record=$(jq -cn \
    --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --arg hook_script "$hook_script" \
    --arg session_name "$session_name" \
    --arg agent_id "$agent_id" \
    --arg openclaw_session_id "$openclaw_session_id" \
    --arg trigger "$trigger" \
    --arg state "$state" \
    --arg content_source "$content_source" \
    --arg wake_message "$wake_message" \
    --arg response "$response" \
    --arg outcome "$outcome" \
    --argjson duration_ms "$duration_ms" \
    "${extra_args[@]}" \
    "{
      timestamp: \$timestamp,
      hook_script: \$hook_script,
      session_name: \$session_name,
      agent_id: \$agent_id,
      openclaw_session_id: \$openclaw_session_id,
      trigger: \$trigger,
      state: \$state,
      content_source: \$content_source,
      wake_message: \$wake_message,
      response: \$response,
      outcome: \$outcome,
      duration_ms: \$duration_ms
    } ${extra_merge}" 2>/dev/null) || return 0

  if [ -z "$record" ]; then
    return 0
  fi

  (
    flock -x -w 2 200 || return 0
    printf '%s\n' "$record" >> "$jsonl_file"
  ) 200>"${jsonl_file}.lock" 2>/dev/null || true
}

# ==========================================================================
# deliver_async_with_logging
# ==========================================================================
# Replaces bare `openclaw agent --session-id ... &` calls in all async
# hook delivery paths. Spawns a background subshell that:
#   1. Calls openclaw and captures the response
#   2. Determines outcome (delivered / no_response)
#   3. Writes a complete JSONL record via write_hook_event_record()
#
# The calling hook exits immediately after this function returns — it does
# NOT wait for the background subshell. The subshell uses explicit
# </dev/null to prevent stdin inheritance from Claude Code's pipe.
#
# Arguments (10 explicit positional parameters + 1 optional):
#   $1  - openclaw_session_id:  OpenClaw session ID for the agent
#   $2  - wake_message:         full wake message body to deliver
#   $3  - jsonl_file:           path to per-session .jsonl log file
#   $4  - hook_entry_ms:        millisecond timestamp from hook start
#   $5  - hook_script:          basename of calling hook script
#   $6  - session_name:         tmux session name
#   $7  - agent_id:             agent identifier
#   $8  - trigger:              event trigger type
#   $9  - state:                detected state
#   $10 - content_source:       how content was obtained
#   $11 - extra_fields_json:    (optional) JSON object string to merge into JSONL record
# Returns:
#   Nothing. Backgrounds a subshell and returns immediately.
# ==========================================================================
deliver_async_with_logging() {
  local openclaw_session_id="$1"
  local wake_message="$2"
  local jsonl_file="$3"
  local hook_entry_ms="$4"
  local hook_script="$5"
  local session_name="$6"
  local agent_id="$7"
  local trigger="$8"
  local state="$9"
  local content_source="${10}"
  local extra_fields_json="${11:-}"

  (
    local response
    response=$(openclaw agent --session-id "$openclaw_session_id" \
      --message "$wake_message" 2>&1) || true
    local outcome="delivered"
    [ -z "$response" ] && outcome="no_response"

    write_hook_event_record \
      "$jsonl_file" "$hook_entry_ms" "$hook_script" "$session_name" \
      "$agent_id" "$openclaw_session_id" "$trigger" "$state" \
      "$content_source" "$wake_message" "$response" "$outcome" \
      "$extra_fields_json"
  ) </dev/null &
}

# ==========================================================================
# deliver_with_mode
# ==========================================================================
# Encapsulates bidirectional-vs-async delivery logic shared by stop-hook.sh,
# notification-idle-hook.sh, and notification-permission-hook.sh.
#
# In bidirectional mode: calls openclaw synchronously, writes a JSONL record,
# parses the response for a decision/reason, and emits safe JSON output for
# Claude Code using jq (not string interpolation). Then exits 0.
#
# In async mode: delegates to deliver_async_with_logging() and exits 0.
#
# Arguments:
#   $1  - hook_mode:             "bidirectional" or "async"
#   $2  - openclaw_session_id:   OpenClaw session ID for the agent
#   $3  - wake_message:          full wake message body to deliver
#   $4  - jsonl_file:            path to per-session .jsonl log file
#   $5  - hook_entry_ms:         millisecond timestamp from hook start
#   $6  - hook_script_name:      basename of calling hook script
#   $7  - session_name:          tmux session name
#   $8  - agent_id:              agent identifier
#   $9  - trigger:               event trigger type
#   $10 - state:                 detected session state
#   $11 - content_source:        how content was obtained
# Returns:
#   In bidirectional mode: may print JSON to stdout for Claude Code decision
#   injection, then exits 0.
#   In async mode: backgrounds delivery subshell, exits 0.
#   Never exits non-zero. Never crashes the calling hook.
# ==========================================================================
deliver_with_mode() {
  local hook_mode="$1"
  local openclaw_session_id="$2"
  local wake_message="$3"
  local jsonl_file="$4"
  local hook_entry_ms="$5"
  local hook_script_name="$6"
  local session_name="$7"
  local agent_id="$8"
  local trigger="$9"
  local state="${10}"
  local content_source="${11}"

  debug_log "DELIVERING: mode=$hook_mode session_id=$openclaw_session_id"

  if [ "$hook_mode" = "bidirectional" ]; then
    debug_log "DELIVERING: bidirectional, waiting for response..."
    local response
    response=$(openclaw agent --session-id "$openclaw_session_id" \
      --message "$wake_message" --json 2>&1 || echo "")
    debug_log "RESPONSE: ${response:0:200}"

    write_hook_event_record \
      "$jsonl_file" "$hook_entry_ms" "$hook_script_name" "$session_name" \
      "$agent_id" "$openclaw_session_id" "$trigger" "$state" \
      "$content_source" "$wake_message" "$response" "sync_delivered"

    if [ -n "$response" ]; then
      local decision
      decision=$(printf '%s' "$response" | jq -r '.decision // ""' 2>/dev/null || echo "")
      local reason
      reason=$(printf '%s' "$response" | jq -r '.reason // ""' 2>/dev/null || echo "")

      if [ "$decision" = "block" ] && [ -n "$reason" ]; then
        jq -cn --arg reason "$reason" '{"decision": "block", "reason": $reason}'
      fi
    fi
    exit 0
  else
    deliver_async_with_logging \
      "$openclaw_session_id" "$wake_message" "$jsonl_file" "$hook_entry_ms" \
      "$hook_script_name" "$session_name" "$agent_id" \
      "$trigger" "$state" "$content_source"
    debug_log "DELIVERED (async with JSONL logging)"
    exit 0
  fi
}

# ==========================================================================
# extract_hook_settings
# ==========================================================================
# Extracts hook_settings fields from registry with three-tier fallback:
#   1. Per-agent hook_settings (agent_data .hook_settings.field)
#   2. Registry-level global hook_settings (.hook_settings.field at root)
#   3. Hardcoded defaults (pane_capture_lines=100, threshold=50, mode=async)
#
# Replaces the 12-line settings extraction block duplicated in stop-hook.sh,
# notification-idle-hook.sh, notification-permission-hook.sh, and
# pre-compact-hook.sh.
#
# Arguments:
#   $1 - registry_path:    path to recovery-registry.json
#   $2 - agent_data_json:  JSON string from lookup_agent_in_registry()
# Returns:
#   Compact JSON on stdout:
#   {"pane_capture_lines":100,"context_pressure_threshold":50,"hook_mode":"async"}
#   On any jq failure, returns the hardcoded defaults JSON string.
#   Never exits non-zero. Never crashes the calling hook.
# ==========================================================================
extract_hook_settings() {
  local registry_path="$1"
  local agent_data_json="$2"

  local global_settings
  global_settings=$(jq -r '.hook_settings // {}' "$registry_path" 2>/dev/null \
    || printf '{}')

  printf '%s' "$agent_data_json" | jq -c \
    --argjson global "$global_settings" \
    '{
      pane_capture_lines:           (.hook_settings.pane_capture_lines           // $global.pane_capture_lines           // 100),
      context_pressure_threshold:   (.hook_settings.context_pressure_threshold   // $global.context_pressure_threshold   // 50),
      hook_mode:                    (.hook_settings.hook_mode                    // $global.hook_mode                    // "async")
    }' 2>/dev/null \
    || printf '{"pane_capture_lines":100,"context_pressure_threshold":50,"hook_mode":"async"}'
}

# ==========================================================================
# detect_session_state
# ==========================================================================
# Detects the current session state from tmux pane content using
# case-insensitive extended regex patterns. Returns a consistent state name
# across all hook event types that use standard pane pattern matching.
#
# State names (in detection priority order):
#   menu             — Claude Code option selection screen
#   permission_prompt — permission or allow dialog
#   idle             — Claude waiting for user input
#   error            — error/failure detected in pane
#   working          — default (no specific pattern matched)
#
# Arguments:
#   $1 - pane_content: string of current tmux pane capture
# Returns:
#   State name string on stdout. Always returns a non-empty string.
#   Never exits non-zero. Never crashes the calling hook.
# ==========================================================================
detect_session_state() {
  local pane_content="$1"

  if printf '%s\n' "$pane_content" | grep -Eiq 'Enter to select|numbered.*option' 2>/dev/null; then
    printf 'menu'
  elif printf '%s\n' "$pane_content" | grep -Eiq 'permission|allow|dangerous' 2>/dev/null; then
    printf 'permission_prompt'
  elif printf '%s\n' "$pane_content" | grep -Eiq 'What can I help|waiting for' 2>/dev/null; then
    printf 'idle'
  elif printf '%s\n' "$pane_content" | grep -Ei 'error|failed|exception' 2>/dev/null \
    | grep -v 'error handling' >/dev/null 2>&1; then
    printf 'error'
  else
    printf 'working'
  fi
}
