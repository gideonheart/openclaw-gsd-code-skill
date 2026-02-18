#!/usr/bin/env bash
set -euo pipefail

# ==========================================================================
# Integration test for deliver_async_with_logging() in lib/hook-utils.sh
# Mocks the openclaw command with bash functions to test the full async
# delivery + JSONL logging pipeline in isolation — no tmux, no real
# openclaw, no Claude Code session.
# ==========================================================================

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_LOG_DIR=$(mktemp -d "/tmp/gsd-test-XXXXXX")
trap 'rm -rf "$TEST_LOG_DIR"' EXIT

source "${SKILL_DIR}/lib/hook-utils.sh"

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
# Test A — Successful async delivery produces JSONL record
# --------------------------------------------------------------------------
printf '\n--- Test A: Successful async delivery ---\n'

# Mock openclaw: return a simulated response
openclaw() {
  printf '{"status":"delivered","agent":"test"}'
}
export -f openclaw

JSONL_FILE="${TEST_LOG_DIR}/async-test.jsonl"
HOOK_ENTRY_MS=$(date +%s%3N)

deliver_async_with_logging \
  "test-session-id" "test wake message" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
  "stop-hook.sh" "test-session" "test-agent" "response_complete" \
  "working" "transcript"

# Wait for background subshell to complete
sleep 2

assert_file_exists "JSONL file created" "$JSONL_FILE"
assert_line_count "exactly 1 line after Test A" 1 "$JSONL_FILE"
assert_jq "outcome is delivered" '.outcome == "delivered"' "$JSONL_FILE"
assert_jq "response contains delivered" '.response | contains("delivered")' "$JSONL_FILE"
assert_jq "duration_ms is a number" '.duration_ms | type == "number"' "$JSONL_FILE"
assert_jq "wake_message is test wake message" '.wake_message == "test wake message"' "$JSONL_FILE"
assert_jq "hook_script is stop-hook.sh" '.hook_script == "stop-hook.sh"' "$JSONL_FILE"
assert_jq "trigger is response_complete" '.trigger == "response_complete"' "$JSONL_FILE"

# --------------------------------------------------------------------------
# Test B — Failed openclaw produces record with no_response outcome
# --------------------------------------------------------------------------
printf '\n--- Test B: Failed openclaw produces no_response ---\n'

# Redefine mock: simulate failure with no output
openclaw() {
  return 1
}
export -f openclaw

JSONL_FILE_FAIL="${TEST_LOG_DIR}/async-fail-test.jsonl"
HOOK_ENTRY_MS=$(date +%s%3N)

deliver_async_with_logging \
  "test-session-id" "test wake message" "$JSONL_FILE_FAIL" "$HOOK_ENTRY_MS" \
  "stop-hook.sh" "test-session" "test-agent" "response_complete" \
  "working" "transcript"

# Wait for background subshell to complete
sleep 2

assert_file_exists "JSONL file created for failure case" "$JSONL_FILE_FAIL"
assert_line_count "exactly 1 line for failure case" 1 "$JSONL_FILE_FAIL"
assert_jq "outcome is no_response" '.outcome == "no_response"' "$JSONL_FILE_FAIL"
assert_jq "response is empty string" '.response == ""' "$JSONL_FILE_FAIL"

# --------------------------------------------------------------------------
# Test C — Wake message with special characters survives async pipeline
# --------------------------------------------------------------------------
printf '\n--- Test C: Special characters survive async pipeline ---\n'

# Redefine mock: simple success
openclaw() {
  printf 'OK'
}
export -f openclaw

JSONL_FILE_SPECIAL="${TEST_LOG_DIR}/async-special-test.jsonl"
HOOK_ENTRY_MS=$(date +%s%3N)
special_wake_message=$(printf 'line1\nline2 with "quotes"\nembedded: {"key":"val"}')

deliver_async_with_logging \
  "test-session-id" "$special_wake_message" "$JSONL_FILE_SPECIAL" "$HOOK_ENTRY_MS" \
  "stop-hook.sh" "test-session" "test-agent" "response_complete" \
  "working" "transcript"

# Wait for background subshell to complete
sleep 2

assert_file_exists "JSONL file created for special chars" "$JSONL_FILE_SPECIAL"
assert_jq "valid JSON" '.' "$JSONL_FILE_SPECIAL"
assert_jq "wake_message contains quotes" '.wake_message | contains("quotes")' "$JSONL_FILE_SPECIAL"
assert_jq "wake_message contains embedded JSON key" '.wake_message | contains("key")' "$JSONL_FILE_SPECIAL"

# --------------------------------------------------------------------------
# Test D — Plan 08-01 tests still pass (no regression)
# --------------------------------------------------------------------------
printf '\n--- Test D: Plan 08-01 regression check ---\n'

if bash "${SKILL_DIR}/tests/test-write-hook-event-record.sh" > /dev/null 2>&1; then
  printf 'PASS: write_hook_event_record tests still pass\n'
else
  printf 'FAIL: write_hook_event_record tests regressed\n'
  exit 1
fi

# --------------------------------------------------------------------------
# Test E — All original functions still defined (no regression)
# --------------------------------------------------------------------------
printf '\n--- Test E: Original functions still defined ---\n'

for function_name in lookup_agent_in_registry extract_last_assistant_response extract_pane_diff format_ask_user_questions write_hook_event_record deliver_async_with_logging; do
  if type "$function_name" > /dev/null 2>&1; then
    printf 'PASS: %s is defined\n' "$function_name"
  else
    printf 'FAIL: %s is not defined\n' "$function_name"
    exit 1
  fi
done

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
printf '\nAll tests passed\n'
