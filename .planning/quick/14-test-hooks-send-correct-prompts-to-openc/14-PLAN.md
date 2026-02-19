---
phase: 14-test-hooks
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - config/recovery-registry.json
  - scripts/test-hook-prompts.sh
autonomous: false
requirements: [QUICK-14]

must_haves:
  truths:
    - "Registry tmux_session_name matches actual running tmux session (warden-main-4)"
    - "Stop hook fires and produces a JSONL record with [ACTION REQUIRED] (not [AVAILABLE ACTIONS])"
    - "Idle hook fires and produces a JSONL record with [ACTION REQUIRED]"
    - "Wake messages contain rendered prompt templates with correct session name and paths"
  artifacts:
    - path: "config/recovery-registry.json"
      provides: "Registry with tmux_session_name matching running session"
      contains: "warden-main-4"
    - path: "scripts/test-hook-prompts.sh"
      provides: "Automated test script for hook prompt verification"
  key_links:
    - from: "scripts/test-hook-prompts.sh"
      to: "logs/warden-main-4.jsonl"
      via: "JSONL record inspection after hook trigger"
      pattern: "ACTION REQUIRED"
---

<objective>
Create an automated test script that verifies hooks send correct prompts to the OpenClaw agent, covering the full v3.2 prompt template system.

Purpose: Validate that the stop hook and idle hook produce wake messages with [ACTION REQUIRED] sections (not the old [AVAILABLE ACTIONS]), that JSONL structured logging works, and that prompt templates render with correct placeholder substitution.

Output: A runnable test script (scripts/test-hook-prompts.sh) and an updated registry pointing at the correct tmux session.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@config/recovery-registry.json
@scripts/stop-hook.sh
@scripts/notification-idle-hook.sh
@lib/hook-preamble.sh
@lib/hook-utils.sh
@scripts/prompts/response-complete.md
@scripts/prompts/idle-prompt.md
@scripts/diagnose-hooks.sh
@logs/
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update registry and clear stale logs</name>
  <files>config/recovery-registry.json</files>
  <action>
1. Update config/recovery-registry.json: change the warden agent's tmux_session_name from "warden-main-3" to "warden-main-4" to match the actual running tmux session.

2. Clear stale log files for a clean test baseline:
   - Remove logs/warden-main-4.jsonl if it exists (old data from before registry fix)
   - Remove logs/warden-main-4.log if it exists
   - Truncate logs/hooks.log to zero bytes (preserve the file, clear contents)
   - Do NOT remove .lock files (they are harmless empty files used by flock)
   - Do NOT touch warden-main-3.* files (historical, may be useful for comparison)

3. Verify the registry change by running: jq '.agents[] | select(.agent_id == "warden") | .tmux_session_name' config/recovery-registry.json
   Expected output: "warden-main-4"

4. Verify tmux session exists: tmux has-session -t warden-main-4
  </action>
  <verify>
Run: jq '.agents[] | select(.agent_id == "warden") | .tmux_session_name' config/recovery-registry.json
Expected: "warden-main-4"
Run: tmux has-session -t warden-main-4 && echo "session exists"
Expected: "session exists"
Run: test ! -f logs/warden-main-4.jsonl && echo "jsonl cleared"
Expected: "jsonl cleared"
  </verify>
  <done>Registry points at warden-main-4, all stale logs cleared, tmux session confirmed running</done>
</task>

<task type="auto">
  <name>Task 2: Create automated hook prompt test script</name>
  <files>scripts/test-hook-prompts.sh</files>
  <action>
Create scripts/test-hook-prompts.sh — an automated end-to-end test script that verifies hooks send correct prompts. The script must follow existing conventions (set -euo pipefail, timestamp logging, pass/fail helpers matching diagnose-hooks.sh style).

The script performs these verification steps in order:

**Step 1: Pre-flight checks**
- Verify registry has correct tmux_session_name for warden (warden-main-4)
- Verify tmux session warden-main-4 exists
- Verify log directory exists (create if needed)
- Record initial JSONL line count (0 if file does not exist)

**Step 2: Trigger stop hook**
- Send "/help" to the warden-main-4 tmux session using: tmux send-keys -t warden-main-4 "/help" Enter
- Wait up to 30 seconds for a new JSONL record to appear in logs/warden-main-4.jsonl (poll every 2 seconds, checking line count > initial count)
- On timeout: FAIL with message indicating no JSONL record appeared

**Step 3: Validate stop hook JSONL record**
- Read the last JSONL record from logs/warden-main-4.jsonl using tail -1 | jq
- Check these fields:
  - .hook_script == "stop-hook.sh" — PASS/FAIL
  - .trigger == "response_complete" — PASS/FAIL
  - .agent_id == "warden" — PASS/FAIL
  - .session_name == "warden-main-4" — PASS/FAIL
  - .outcome contains "delivered" (either "delivered" or "sync_delivered") — PASS/FAIL
  - .duration_ms is a number > 0 — PASS/FAIL

**Step 4: Validate [ACTION REQUIRED] in wake message**
- From the same JSONL record, extract .wake_message
- Check that wake_message contains "[ACTION REQUIRED]" (literal string match) — PASS/FAIL with "v3.2 [ACTION REQUIRED] present"
- Check that wake_message does NOT contain "[AVAILABLE ACTIONS]" — PASS/FAIL with "no legacy [AVAILABLE ACTIONS]"
- Check that wake_message contains "menu-driver.sh" (rendered template placeholder) — PASS/FAIL
- Check that wake_message contains "warden-main-4" (session name substituted) — PASS/FAIL

**Step 5: Validate wake message structure**
- Check wake_message contains "[SESSION IDENTITY]" — PASS/FAIL
- Check wake_message contains "[TRIGGER]" — PASS/FAIL
- Check wake_message contains "type: response_complete" — PASS/FAIL
- Check wake_message contains "[CONTENT]" — PASS/FAIL
- Check wake_message contains "[STATE HINT]" — PASS/FAIL
- Check wake_message contains "[CONTEXT PRESSURE]" — PASS/FAIL

**Step 6: Wait for idle hook (optional, time-bounded)**
- Record current JSONL line count
- Print info: "Waiting up to 60s for idle hook to fire..."
- Wait up to 60 seconds for another JSONL record (poll every 5 seconds)
- If a new record appears with .trigger == "idle_prompt":
  - PASS: "idle hook fired"
  - Check .wake_message contains "[ACTION REQUIRED]" — PASS/FAIL
  - Check .wake_message does NOT contain "[AVAILABLE ACTIONS]" — PASS/FAIL
  - Check .wake_message contains "idle-prompt" related content (the idle template starts with "Claude is waiting for user input") — PASS/FAIL
- If timeout: INFO "idle hook did not fire within 60s (this is OK — it depends on Claude Code state)" — not a failure

**Summary section:**
- Print total PASS/FAIL/INFO counts
- Print "ALL CRITICAL CHECKS PASSED" or "N check(s) FAILED" like diagnose-hooks.sh does
- Exit 0 if all critical checks passed, exit 1 if any FAIL

Implementation notes:
- Use the same pass/fail/info helper functions as diagnose-hooks.sh (colored output)
- Use SKILL_ROOT derived from BASH_SOURCE[0] like other scripts
- All log paths use SKILL_ROOT/logs/ (not /tmp)
- All jq piping uses printf '%s' (not echo), consistent with codebase convention
- Add a usage header: "Usage: scripts/test-hook-prompts.sh [--skip-idle]" with --skip-idle flag to skip the 60s idle wait
- Make the script executable (chmod +x)
  </action>
  <verify>
Run: bash -n scripts/test-hook-prompts.sh (syntax check passes)
Run: scripts/test-hook-prompts.sh --help shows usage
Run: test -x scripts/test-hook-prompts.sh && echo "executable"
Expected: "executable"
  </verify>
  <done>Test script exists, passes syntax check, is executable, and covers all 6 verification steps from the user's test plan</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Run test script and verify hook prompts end-to-end</name>
  <files>scripts/test-hook-prompts.sh</files>
  <action>
HUMAN VERIFICATION: Run the test script and confirm all checks pass.

What was built:
- Registry updated to warden-main-4
- Automated test script at scripts/test-hook-prompts.sh that verifies stop hook and idle hook send correct v3.2 prompts

How to verify:
1. Run: scripts/test-hook-prompts.sh
2. The script sends "/help" to warden-main-4 to trigger the stop hook
3. It waits for JSONL records and validates all fields and wake message structure
4. All PASS checks should be green. Any FAIL indicates a real issue.
5. To skip idle hook wait: scripts/test-hook-prompts.sh --skip-idle
  </action>
  <verify>All PASS checks green in test script output, zero FAIL results</verify>
  <done>User confirms test script output shows all critical checks passing</done>
</task>

</tasks>

<verification>
- Registry tmux_session_name matches running session (warden-main-4)
- Test script runs without errors and produces structured PASS/FAIL output
- Stop hook JSONL record contains [ACTION REQUIRED], not [AVAILABLE ACTIONS]
- Wake message contains all v2 format sections ([SESSION IDENTITY], [TRIGGER], [CONTENT], [STATE HINT], [CONTEXT PRESSURE], [ACTION REQUIRED])
- Prompt template placeholders ({SESSION_NAME}, {MENU_DRIVER_PATH}) are substituted with actual values
</verification>

<success_criteria>
1. config/recovery-registry.json has tmux_session_name "warden-main-4" for warden agent
2. scripts/test-hook-prompts.sh exists, is executable, passes bash -n syntax check
3. Running the test script triggers the stop hook and validates JSONL output
4. All critical checks pass (v3.2 [ACTION REQUIRED] present, no [AVAILABLE ACTIONS], correct wake message structure)
</success_criteria>

<output>
After completion, create `.planning/quick/14-test-hooks-send-correct-prompts-to-openc/14-SUMMARY.md`
</output>
