#!/usr/bin/env bash
# lib/hook-utils.sh - Shared extraction functions for GSD hook scripts
# Sourced by stop-hook.sh and pre-tool-use-hook.sh only.
# Contains ONLY function definitions - no side effects on source.
# No set -euo pipefail here - the caller sets shell options.

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
  local previous_file="/tmp/gsd-pane-prev-${session_name}.txt"
  local lock_file="/tmp/gsd-pane-lock-${session_name}"

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
