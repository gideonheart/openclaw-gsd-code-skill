#!/usr/bin/env bash
# lib/hook-utils.sh - Shared utility functions for GSD hook scripts
# Sourced by all 6 hook scripts (registry lookup, extraction, formatting).
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
# Arguments (12 explicit positional parameters):
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

  local hook_exit_ms
  hook_exit_ms=$(date +%s%3N)
  local duration_ms=$((hook_exit_ms - hook_entry_ms))

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
    '{
      timestamp: $timestamp,
      hook_script: $hook_script,
      session_name: $session_name,
      agent_id: $agent_id,
      openclaw_session_id: $openclaw_session_id,
      trigger: $trigger,
      state: $state,
      content_source: $content_source,
      wake_message: $wake_message,
      response: $response,
      outcome: $outcome,
      duration_ms: $duration_ms
    }' 2>/dev/null) || return 0

  if [ -z "$record" ]; then
    return 0
  fi

  (
    flock -x -w 2 200 || return 0
    printf '%s\n' "$record" >> "$jsonl_file"
  ) 200>"${jsonl_file}.lock" 2>/dev/null || true
}
