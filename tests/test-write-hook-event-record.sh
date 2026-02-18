#!/usr/bin/env bash
set -euo pipefail

# ==========================================================================
# Unit test for write_hook_event_record() in lib/hook-utils.sh
# Runs in complete isolation — no tmux, no openclaw, no Claude Code session.
# ==========================================================================

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_LOG_DIR=$(mktemp -d "/tmp/gsd-test-XXXXXX")
trap 'rm -rf "$TEST_LOG_DIR"' EXIT

source "${SKILL_DIR}/lib/hook-utils.sh"

JSONL_FILE="${TEST_LOG_DIR}/test.jsonl"

# --------------------------------------------------------------------------
# Assertion helpers
# --------------------------------------------------------------------------

assert_jq() {
  local description="$1"
  local filter="$2"
  local file="$3"
  if jq -e "$filter" "$file" > /dev/null 2>&1; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    exit 1
  fi
}

assert_line_count() {
  local description="$1"
  local expected="$2"
  local file="$3"
  local actual
  actual=$(wc -l < "$file")
  if [ "$actual" -eq "$expected" ]; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s (expected %s lines, got %s)\n' "$description" "$expected" "$actual"
    exit 1
  fi
}

assert_file_exists() {
  local description="$1"
  local file="$2"
  if [ -f "$file" ]; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    exit 1
  fi
}

# --------------------------------------------------------------------------
# Test A — Basic record with clean strings
# --------------------------------------------------------------------------
printf '\n--- Test A: Basic record with clean strings ---\n'

HOOK_ENTRY_MS=$(date +%s%3N)

write_hook_event_record \
  "$JSONL_FILE" "$HOOK_ENTRY_MS" "stop-hook.sh" "test-session" \
  "test-agent" "test-id-123" "response_complete" "working" \
  "transcript" "Hello world" '{"status":"ok"}' "delivered"

assert_file_exists "JSONL file created" "$JSONL_FILE"
assert_line_count "exactly 1 line after Test A" 1 "$JSONL_FILE"
assert_jq "valid JSON" '.' "$JSONL_FILE"
assert_jq "duration_ms is a number" '.duration_ms | type == "number"' "$JSONL_FILE"
assert_jq "hook_script is stop-hook.sh" '.hook_script == "stop-hook.sh"' "$JSONL_FILE"
assert_jq "outcome is delivered" '.outcome == "delivered"' "$JSONL_FILE"
assert_jq "session_name is test-session" '.session_name == "test-session"' "$JSONL_FILE"
assert_jq "agent_id is test-agent" '.agent_id == "test-agent"' "$JSONL_FILE"
assert_jq "trigger is response_complete" '.trigger == "response_complete"' "$JSONL_FILE"
assert_jq "content_source is transcript" '.content_source == "transcript"' "$JSONL_FILE"
assert_jq "timestamp is ISO 8601" '.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "$JSONL_FILE"

# --------------------------------------------------------------------------
# Test B — Strings with newlines, quotes, and ANSI codes
# --------------------------------------------------------------------------
printf '\n--- Test B: Strings with newlines, quotes, and ANSI codes ---\n'

HOOK_ENTRY_MS=$(date +%s%3N)
SPECIAL_WAKE_MESSAGE=$(printf 'line1\nline2 with "quotes"\nANSI: \033[31mred\033[0m')

write_hook_event_record \
  "$JSONL_FILE" "$HOOK_ENTRY_MS" "stop-hook.sh" "test-session" \
  "test-agent" "test-id-123" "response_complete" "working" \
  "transcript" "$SPECIAL_WAKE_MESSAGE" '{"status":"ok"}' "delivered"

assert_line_count "exactly 2 lines after Test B (appended)" 2 "$JSONL_FILE"

# Use tail -1 to check the second record specifically
LAST_RECORD_FILE="${TEST_LOG_DIR}/last-record.json"
tail -1 "$JSONL_FILE" > "$LAST_RECORD_FILE"

assert_jq "second record is valid JSON" '.' "$LAST_RECORD_FILE"
assert_jq "wake_message contains quotes" '.wake_message | contains("quotes")' "$LAST_RECORD_FILE"
assert_jq "wake_message contains newlines (escaped)" '.wake_message | contains("\n")' "$LAST_RECORD_FILE"

# --------------------------------------------------------------------------
# Test C — Empty response field
# --------------------------------------------------------------------------
printf '\n--- Test C: Empty response field ---\n'

HOOK_ENTRY_MS=$(date +%s%3N)

write_hook_event_record \
  "$JSONL_FILE" "$HOOK_ENTRY_MS" "session-end-hook.sh" "test-session" \
  "test-agent" "test-id-123" "session_end" "idle" \
  "none" "" "" "no_response"

assert_line_count "exactly 3 lines after Test C (appended)" 3 "$JSONL_FILE"

LAST_RECORD_FILE="${TEST_LOG_DIR}/last-record-c.json"
tail -1 "$JSONL_FILE" > "$LAST_RECORD_FILE"

assert_jq "response is empty string (not null)" '.response == ""' "$LAST_RECORD_FILE"
assert_jq "outcome is no_response" '.outcome == "no_response"' "$LAST_RECORD_FILE"
assert_jq "hook_script is session-end-hook.sh" '.hook_script == "session-end-hook.sh"' "$LAST_RECORD_FILE"

# --------------------------------------------------------------------------
# Test D — All records are valid JSONL (parse entire file)
# --------------------------------------------------------------------------
printf '\n--- Test D: All records are valid JSONL ---\n'

# jq processes each line independently — exits non-zero if any line is invalid
if jq -e '.' "$JSONL_FILE" > /dev/null 2>&1; then
  printf 'PASS: entire file is valid JSONL\n'
else
  printf 'FAIL: entire file is not valid JSONL\n'
  exit 1
fi

TOTAL_LINES=$(wc -l < "$JSONL_FILE")
if [ "$TOTAL_LINES" -eq 3 ]; then
  printf 'PASS: file has exactly 3 records total\n'
else
  printf 'FAIL: expected 3 records, got %s\n' "$TOTAL_LINES"
  exit 1
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
printf '\nAll tests passed\n'
