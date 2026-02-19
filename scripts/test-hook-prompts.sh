#!/usr/bin/env bash
set -euo pipefail

# test-hook-prompts.sh - End-to-end test that verifies hooks send correct v3.2 prompts
# Usage: scripts/test-hook-prompts.sh [--skip-idle]
#
# Verifies:
#   1. Pre-flight: registry and tmux session sanity
#   2. Stop hook fires on /help trigger and produces JSONL record
#   3. JSONL record fields: hook_script, trigger, agent_id, session_name, outcome, duration_ms
#   4. Wake message contains [ACTION REQUIRED] (v3.2), not [AVAILABLE ACTIONS] (legacy)
#   5. Wake message structure: [SESSION IDENTITY], [TRIGGER], [CONTENT], [STATE HINT], [CONTEXT PRESSURE]
#   6. Idle hook fires within 60s and its wake message also uses [ACTION REQUIRED]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY_PATH="${SKILL_ROOT}/config/recovery-registry.json"
LOG_DIR="${SKILL_ROOT}/logs"

SKIP_IDLE=false

for argument in "$@"; do
  case "$argument" in
    --skip-idle) SKIP_IDLE=true ;;
    --help|-h)
      echo "Usage: scripts/test-hook-prompts.sh [--skip-idle]"
      echo ""
      echo "End-to-end test that verifies hooks send correct v3.2 prompts to OpenClaw."
      echo ""
      echo "Steps:"
      echo "  1. Pre-flight: registry tmux_session_name + tmux session existence"
      echo "  2. Trigger stop hook via /help sent to the warden tmux session"
      echo "  3. Validate JSONL record fields (hook_script, trigger, agent_id, session_name, outcome)"
      echo "  4. Validate [ACTION REQUIRED] present, [AVAILABLE ACTIONS] absent in wake_message"
      echo "  5. Validate wake message structure sections"
      echo "  6. Wait up to 60s for idle hook (skippable with --skip-idle)"
      echo ""
      echo "Options:"
      echo "  --skip-idle   Skip the 60-second idle hook wait (step 6)"
      echo "  --help        Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $argument" >&2; exit 1 ;;
  esac
done

# --------------------------------------------------------------------------
# Output helpers (matching diagnose-hooks.sh style)
# --------------------------------------------------------------------------
pass() { PASSED_CHECKS=$((PASSED_CHECKS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { FAILED_CHECKS=$((FAILED_CHECKS + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
info() { printf '  \033[36mINFO\033[0m %s\n' "$*"; }

PASSED_CHECKS=0
FAILED_CHECKS=0

echo ""
echo "=========================================="
echo "  GSD Hook Prompt End-to-End Test"
echo "  Time: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "=========================================="
echo ""

# --------------------------------------------------------------------------
# Step 1: Pre-flight checks
# --------------------------------------------------------------------------
echo "--- Step 1: Pre-flight checks ---"

WARDEN_SESSION=""

if [ ! -f "$REGISTRY_PATH" ]; then
  fail "Registry file not found: $REGISTRY_PATH"
  echo ""
  echo "Cannot proceed without registry."
  exit 1
fi

WARDEN_SESSION=$(jq -r '.agents[] | select(.agent_id == "warden") | .tmux_session_name // ""' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")

if [ -z "$WARDEN_SESSION" ]; then
  fail "No warden agent entry or tmux_session_name is empty in registry"
  exit 1
fi

if [ "$WARDEN_SESSION" = "warden-main-4" ]; then
  pass "Registry tmux_session_name = warden-main-4"
else
  fail "Registry tmux_session_name = ${WARDEN_SESSION} (expected warden-main-4)"
fi

if tmux has-session -t "$WARDEN_SESSION" 2>/dev/null; then
  pass "tmux session '${WARDEN_SESSION}' exists"
else
  fail "tmux session '${WARDEN_SESSION}' does NOT exist"
  echo ""
  echo "Cannot proceed: tmux session not running."
  exit 1
fi

mkdir -p "$LOG_DIR"
pass "Log directory exists: ${LOG_DIR}"

JSONL_FILE="${LOG_DIR}/${WARDEN_SESSION}.jsonl"

initial_line_count=0
if [ -f "$JSONL_FILE" ]; then
  initial_line_count=$(wc -l < "$JSONL_FILE" 2>/dev/null || echo "0")
fi
info "Initial JSONL line count: ${initial_line_count}"

echo ""

# --------------------------------------------------------------------------
# Step 2: Trigger stop hook via /help
# --------------------------------------------------------------------------
echo "--- Step 2: Trigger stop hook ---"

info "Sending '/help' to tmux session ${WARDEN_SESSION} ..."
tmux send-keys -t "$WARDEN_SESSION" "/help" Enter

info "Waiting up to 30s for JSONL record to appear ..."

stop_hook_found=false
wait_seconds=0
while [ "$wait_seconds" -lt 30 ]; do
  sleep 2
  wait_seconds=$((wait_seconds + 2))

  if [ -f "$JSONL_FILE" ]; then
    current_line_count=$(wc -l < "$JSONL_FILE" 2>/dev/null || echo "0")
    if [ "$current_line_count" -gt "$initial_line_count" ]; then
      stop_hook_found=true
      pass "JSONL record appeared after ${wait_seconds}s (line count: ${initial_line_count} -> ${current_line_count})"
      break
    fi
  fi
done

if [ "$stop_hook_found" = false ]; then
  fail "No JSONL record appeared within 30s — stop hook did not fire or did not deliver"
  info "Check logs/hooks.log and logs/${WARDEN_SESSION}.log for details"
  echo ""
  echo "=========================================="
  echo "  Results: ${PASSED_CHECKS} passed / ${FAILED_CHECKS} failed"
  echo "=========================================="
  exit 1
fi

echo ""

# --------------------------------------------------------------------------
# Step 3: Validate stop hook JSONL record fields
# --------------------------------------------------------------------------
echo "--- Step 3: Validate JSONL record fields ---"

last_jsonl_record=$(tail -1 "$JSONL_FILE" 2>/dev/null || echo "")

if [ -z "$last_jsonl_record" ]; then
  fail "Could not read last JSONL record from ${JSONL_FILE}"
  exit 1
fi

record_hook_script=$(printf '%s' "$last_jsonl_record" | jq -r '.hook_script // ""' 2>/dev/null || echo "")
record_trigger=$(printf '%s' "$last_jsonl_record" | jq -r '.trigger // ""' 2>/dev/null || echo "")
record_agent_id=$(printf '%s' "$last_jsonl_record" | jq -r '.agent_id // ""' 2>/dev/null || echo "")
record_session_name=$(printf '%s' "$last_jsonl_record" | jq -r '.session_name // ""' 2>/dev/null || echo "")
record_outcome=$(printf '%s' "$last_jsonl_record" | jq -r '.outcome // ""' 2>/dev/null || echo "")
record_duration_ms=$(printf '%s' "$last_jsonl_record" | jq -r '.duration_ms // ""' 2>/dev/null || echo "")

if [ "$record_hook_script" = "stop-hook.sh" ]; then
  pass "hook_script == stop-hook.sh"
else
  fail "hook_script == '${record_hook_script}' (expected stop-hook.sh)"
fi

if [ "$record_trigger" = "response_complete" ]; then
  pass "trigger == response_complete"
else
  fail "trigger == '${record_trigger}' (expected response_complete)"
fi

if [ "$record_agent_id" = "warden" ]; then
  pass "agent_id == warden"
else
  fail "agent_id == '${record_agent_id}' (expected warden)"
fi

if [ "$record_session_name" = "warden-main-4" ]; then
  pass "session_name == warden-main-4"
else
  fail "session_name == '${record_session_name}' (expected warden-main-4)"
fi

case "$record_outcome" in
  delivered|sync_delivered)
    pass "outcome == '${record_outcome}' (delivered)"
    ;;
  *)
    fail "outcome == '${record_outcome}' (expected delivered or sync_delivered)"
    ;;
esac

if [ -n "$record_duration_ms" ] && [ "$record_duration_ms" -gt 0 ] 2>/dev/null; then
  pass "duration_ms == ${record_duration_ms} (> 0)"
else
  fail "duration_ms == '${record_duration_ms}' (expected numeric > 0)"
fi

echo ""

# --------------------------------------------------------------------------
# Step 4: Validate [ACTION REQUIRED] in wake message
# --------------------------------------------------------------------------
echo "--- Step 4: Validate [ACTION REQUIRED] in wake message ---"

wake_message=$(printf '%s' "$last_jsonl_record" | jq -r '.wake_message // ""' 2>/dev/null || echo "")

if [ -z "$wake_message" ]; then
  fail "wake_message field is empty in JSONL record"
else
  if printf '%s' "$wake_message" | grep -qF '[ACTION REQUIRED]'; then
    pass "v3.2 [ACTION REQUIRED] present in wake_message"
  else
    fail "v3.2 [ACTION REQUIRED] NOT found in wake_message"
  fi

  if printf '%s' "$wake_message" | grep -qF '[AVAILABLE ACTIONS]'; then
    fail "Legacy [AVAILABLE ACTIONS] found in wake_message (should be replaced by [ACTION REQUIRED])"
  else
    pass "No legacy [AVAILABLE ACTIONS] in wake_message"
  fi

  if printf '%s' "$wake_message" | grep -qF 'menu-driver.sh'; then
    pass "menu-driver.sh present in wake_message (template placeholder rendered)"
  else
    fail "menu-driver.sh NOT found in wake_message (template placeholder substitution may have failed)"
  fi

  if printf '%s' "$wake_message" | grep -qF 'warden-main-4'; then
    pass "warden-main-4 present in wake_message (session name substituted)"
  else
    fail "warden-main-4 NOT found in wake_message (session name placeholder not substituted)"
  fi
fi

echo ""

# --------------------------------------------------------------------------
# Step 5: Validate wake message structure sections
# --------------------------------------------------------------------------
echo "--- Step 5: Validate wake message structure ---"

for expected_section in '[SESSION IDENTITY]' '[TRIGGER]' '[CONTENT]' '[STATE HINT]' '[CONTEXT PRESSURE]'; do
  if printf '%s' "$wake_message" | grep -qF "$expected_section"; then
    pass "${expected_section} section present"
  else
    fail "${expected_section} section NOT found in wake_message"
  fi
done

if printf '%s' "$wake_message" | grep -qF 'type: response_complete'; then
  pass "type: response_complete present in [TRIGGER] section"
else
  fail "type: response_complete NOT found in wake_message"
fi

echo ""

# --------------------------------------------------------------------------
# Step 6: Wait for idle hook (optional, time-bounded)
# --------------------------------------------------------------------------
echo "--- Step 6: Idle hook check ---"

if [ "$SKIP_IDLE" = true ]; then
  info "Idle hook wait skipped (--skip-idle flag provided)"
  echo ""
else
  post_stop_line_count=$(wc -l < "$JSONL_FILE" 2>/dev/null || echo "0")
  info "Waiting up to 60s for idle hook to fire ..."

  idle_hook_found=false
  idle_wait_seconds=0
  while [ "$idle_wait_seconds" -lt 60 ]; do
    sleep 5
    idle_wait_seconds=$((idle_wait_seconds + 5))

    if [ -f "$JSONL_FILE" ]; then
      current_line_count=$(wc -l < "$JSONL_FILE" 2>/dev/null || echo "0")
      if [ "$current_line_count" -gt "$post_stop_line_count" ]; then
        idle_record=$(tail -1 "$JSONL_FILE" 2>/dev/null || echo "")
        idle_trigger=$(printf '%s' "$idle_record" | jq -r '.trigger // ""' 2>/dev/null || echo "")

        if [ "$idle_trigger" = "idle_prompt" ]; then
          idle_hook_found=true
          pass "Idle hook fired after ${idle_wait_seconds}s"

          idle_wake_message=$(printf '%s' "$idle_record" | jq -r '.wake_message // ""' 2>/dev/null || echo "")

          if printf '%s' "$idle_wake_message" | grep -qF '[ACTION REQUIRED]'; then
            pass "[ACTION REQUIRED] present in idle hook wake_message"
          else
            fail "[ACTION REQUIRED] NOT found in idle hook wake_message"
          fi

          if printf '%s' "$idle_wake_message" | grep -qF '[AVAILABLE ACTIONS]'; then
            fail "Legacy [AVAILABLE ACTIONS] found in idle hook wake_message"
          else
            pass "No legacy [AVAILABLE ACTIONS] in idle hook wake_message"
          fi

          if printf '%s' "$idle_wake_message" | grep -qF 'Claude is waiting for user input'; then
            pass "Idle template content present (idle-prompt.md rendered)"
          else
            fail "Expected idle template opening not found in idle hook wake_message"
          fi

          break
        else
          post_stop_line_count="$current_line_count"
        fi
      fi
    fi
  done

  if [ "$idle_hook_found" = false ]; then
    info "Idle hook did not fire within 60s (this is OK — depends on Claude Code state)"
  fi

  echo ""
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo "=========================================="
total_checks=$((PASSED_CHECKS + FAILED_CHECKS))
echo "  Results: ${PASSED_CHECKS}/${total_checks} checks passed  |  ${FAILED_CHECKS} failed"
echo "=========================================="
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo "ALL CRITICAL CHECKS PASSED"
  echo ""
  exit 0
else
  echo "${FAILED_CHECKS} check(s) FAILED"
  echo ""
  echo "Debugging tips:"
  echo "  tail -f ${LOG_DIR}/${WARDEN_SESSION}.log"
  echo "  tail -5 ${JSONL_FILE} | jq ."
  echo "  scripts/diagnose-hooks.sh warden"
  echo ""
  exit 1
fi
