---
phase: quick-12
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/hook-utils.sh
  - scripts/notification-idle-hook.sh
  - scripts/notification-permission-hook.sh
  - scripts/stop-hook.sh
autonomous: true
requirements: []

must_haves:
  truths:
    - "Delivery logic exists in exactly one place (lib/hook-utils.sh), not triplicated across 3 hooks"
    - "JSON output from bidirectional hooks uses jq for safe construction, never bare string interpolation"
    - "write_hook_event_record has a single jq template block, not two identical copies"
    - "No stale comments claim pre-compact uses different patterns when it actually uses detect_session_state()"
  artifacts:
    - path: "lib/hook-utils.sh"
      provides: "deliver_with_mode() function handling bidirectional vs async delivery"
      contains: "deliver_with_mode"
    - path: "lib/hook-utils.sh"
      provides: "Single jq template in write_hook_event_record"
    - path: "scripts/notification-idle-hook.sh"
      provides: "Calls deliver_with_mode() instead of inline delivery block"
      contains: "deliver_with_mode"
    - path: "scripts/notification-permission-hook.sh"
      provides: "Calls deliver_with_mode() instead of inline delivery block"
      contains: "deliver_with_mode"
    - path: "scripts/stop-hook.sh"
      provides: "Calls deliver_with_mode() instead of inline delivery block"
      contains: "deliver_with_mode"
  key_links:
    - from: "scripts/notification-idle-hook.sh"
      to: "lib/hook-utils.sh"
      via: "deliver_with_mode() function call"
      pattern: "deliver_with_mode"
    - from: "scripts/notification-permission-hook.sh"
      to: "lib/hook-utils.sh"
      via: "deliver_with_mode() function call"
      pattern: "deliver_with_mode"
    - from: "scripts/stop-hook.sh"
      to: "lib/hook-utils.sh"
      via: "deliver_with_mode() function call"
      pattern: "deliver_with_mode"
---

<objective>
Fix the 4 remaining v3.1 retrospective issues: delivery triplication across 3 hooks, JSON injection in bidirectional echo responses, write_hook_event_record internal duplication, and a stale comment about pre-compact state detection.

Purpose: Eliminate the last copy-paste debt and a security bug identified in Quick Tasks 10-11.
Output: Cleaner hook-utils.sh with two new/refactored functions, three thinned hook scripts, zero JSON injection vectors.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@lib/hook-utils.sh
@scripts/notification-idle-hook.sh
@scripts/notification-permission-hook.sh
@scripts/stop-hook.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Extract deliver_with_mode() into hook-utils.sh and replace inline delivery blocks in 3 hooks</name>
  <files>
    lib/hook-utils.sh
    scripts/notification-idle-hook.sh
    scripts/notification-permission-hook.sh
    scripts/stop-hook.sh
  </files>
  <action>
This task fixes Issue 1 (delivery triplication) and Issue 2 (JSON injection) together, because the injection bug lives inside the triplicated code.

**In lib/hook-utils.sh**, add a new function `deliver_with_mode()` between `deliver_async_with_logging()` and `extract_hook_settings()`. This function encapsulates the bidirectional-vs-async delivery logic currently duplicated across notification-idle-hook.sh (lines 139-169), notification-permission-hook.sh (lines 140-170), and stop-hook.sh (lines 177-207).

Function signature (self-explanatory names, no abbreviations per CLAUDE.md):
```bash
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
```

Function body:
- If `hook_mode` = "bidirectional":
  - Call `openclaw agent --session-id ... --message ... --json 2>&1 || echo ""`
  - Call `write_hook_event_record` with outcome "sync_delivered"
  - Parse response for decision/reason using `jq -r`
  - CRITICAL FIX (Issue 2 - JSON injection): Instead of `echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"`, use:
    ```bash
    jq -cn --arg reason "$REASON" '{"decision": "block", "reason": $reason}'
    ```
    This prevents injection via $REASON containing quotes, backslashes, or newlines.
  - Exit 0
- Else (async mode):
  - Call `deliver_async_with_logging` with all parameters
  - Exit 0

Include the same debug_log calls as the current inline code:
- `debug_log "DELIVERING: mode=$hook_mode session_id=$openclaw_session_id"`
- `debug_log "DELIVERING: bidirectional, waiting for response..."` (bidirectional branch)
- `debug_log "RESPONSE: ${RESPONSE:0:200}"` (after response)
- `debug_log "DELIVERED (async with JSONL logging)"` (async branch)

**In each of the 3 hook scripts**, replace the entire "HYBRID MODE DELIVERY" section (the if/else block plus the TRIGGER and CONTENT_SOURCE variable declarations that precede it) with a single function call:

For notification-idle-hook.sh, replace lines 135-169 with:
```bash
deliver_with_mode "$HOOK_MODE" "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" \
  "$JSONL_FILE" "$HOOK_ENTRY_MS" "$HOOK_SCRIPT_NAME" "$SESSION_NAME" \
  "$AGENT_ID" "idle_prompt" "$STATE" "pane"
```

For notification-permission-hook.sh, replace lines 136-170 with:
```bash
deliver_with_mode "$HOOK_MODE" "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" \
  "$JSONL_FILE" "$HOOK_ENTRY_MS" "$HOOK_SCRIPT_NAME" "$SESSION_NAME" \
  "$AGENT_ID" "permission_prompt" "$STATE" "pane"
```

For stop-hook.sh, replace lines 174-207 with:
```bash
deliver_with_mode "$HOOK_MODE" "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" \
  "$JSONL_FILE" "$HOOK_ENTRY_MS" "$HOOK_SCRIPT_NAME" "$SESSION_NAME" \
  "$AGENT_ID" "response_complete" "$STATE" "$CONTENT_SOURCE"
```

Note: stop-hook.sh uses dynamic `$CONTENT_SOURCE` (transcript/pane_diff/raw_pane_tail) while the notification hooks always use "pane". The function handles this via parameter passing.

Keep the section comment header (e.g., "# 10. HYBRID MODE DELIVERY") but make it just the single function call.
  </action>
  <verify>
1. `grep -c 'deliver_with_mode' lib/hook-utils.sh` returns at least 1 (function definition)
2. `grep -c 'deliver_with_mode' scripts/notification-idle-hook.sh scripts/notification-permission-hook.sh scripts/stop-hook.sh` shows 1 per file
3. `grep -rn 'echo.*decision.*block.*reason' scripts/` returns zero matches (JSON injection eliminated)
4. `grep -c 'jq -cn --arg reason' lib/hook-utils.sh` returns 1 (safe JSON construction)
5. `bash -n lib/hook-utils.sh && bash -n scripts/notification-idle-hook.sh && bash -n scripts/notification-permission-hook.sh && bash -n scripts/stop-hook.sh` all pass syntax check
  </verify>
  <done>
- deliver_with_mode() exists in lib/hook-utils.sh with bidirectional and async branches
- All 3 hook scripts call deliver_with_mode() instead of inline delivery blocks (~90 lines removed total)
- JSON injection bug fixed: jq -cn --arg used instead of echo with string interpolation
- All 4 files pass bash -n syntax check
  </done>
</task>

<task type="auto">
  <name>Task 2: Deduplicate write_hook_event_record jq blocks and remove stale comment</name>
  <files>lib/hook-utils.sh</files>
  <action>
This task fixes Issue 3 (internal duplication in write_hook_event_record) and Issue 4 (stale comment on detect_session_state).

**Issue 3 fix — write_hook_event_record (lines 202-258):**

Currently there are two nearly identical 28-line jq blocks: one for when extra_fields_json is non-empty (lines 203-230) and one for when it is empty (lines 232-258). The ONLY difference is that the first block has `--argjson extra_fields "$extra_fields_json"` and appends `+ $extra_fields` to the jq filter.

Replace the if/else with a single jq invocation that conditionally handles extra_fields:

```bash
local extra_args=()
local extra_merge=""
if [ -n "$extra_fields_json" ]; then
  extra_args=(--argjson extra_fields "$extra_fields_json")
  extra_merge='+ $extra_fields'
fi

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
```

IMPORTANT: When extra_args is empty, `"${extra_args[@]}"` expands to nothing (standard bash array behavior), which is exactly what we want. The extra_merge variable is either empty string or `+ $extra_fields`, appended directly into the jq filter string.

This eliminates ~28 duplicate lines while preserving identical behavior for both code paths.

**Issue 4 fix — stale comment (lines 386-391):**

The detect_session_state() docstring contains a "Note:" block (lines 386-391) that says:
> "pre-compact-hook.sh uses different patterns and state names (case-sensitive grep, "Choose an option:", "Continue this conversation", "active" fallback). Until pre-compact TUI text is empirically verified, that hook may retain its own inline detection rather than calling this function."

This is stale because Phase 13 migrated pre-compact-hook.sh to use detect_session_state(). Delete lines 386-391 entirely (the "Note:" paragraph). The function docstring ends cleanly at line 385 ("Never exits non-zero. Never crashes the calling hook.").
  </action>
  <verify>
1. `bash -n lib/hook-utils.sh` passes syntax check
2. `grep -c 'pre-compact-hook.sh uses different patterns' lib/hook-utils.sh` returns 0 (stale comment removed)
3. `grep -c 'extra_merge' lib/hook-utils.sh` returns at least 1 (deduplication approach present)
4. Count the jq template blocks in write_hook_event_record: `grep -A2 'timestamp: \$timestamp' lib/hook-utils.sh | grep -c 'timestamp'` returns exactly 1 (single template, not two)
  </verify>
  <done>
- write_hook_event_record has a single jq template block with conditional extra_fields handling (~28 lines removed)
- Stale "Note:" comment about pre-compact using different patterns is deleted
- lib/hook-utils.sh passes bash -n syntax check
  </done>
</task>

</tasks>

<verification>
After both tasks complete:

1. All 4 files pass syntax check: `bash -n lib/hook-utils.sh && bash -n scripts/notification-idle-hook.sh && bash -n scripts/notification-permission-hook.sh && bash -n scripts/stop-hook.sh`
2. Zero JSON injection vectors: `grep -rn 'echo.*{.*decision.*reason.*}' scripts/ lib/` returns no matches
3. Zero delivery triplication: `grep -rn 'openclaw agent --session-id' scripts/notification-idle-hook.sh scripts/notification-permission-hook.sh scripts/stop-hook.sh` returns 0 matches (all delivery goes through hook-utils.sh)
4. Zero stale pre-compact comments: `grep -c 'pre-compact-hook.sh uses different' lib/hook-utils.sh` returns 0
5. Single jq template in write_hook_event_record: visual inspection confirms one block, not two
</verification>

<success_criteria>
- deliver_with_mode() function exists in lib/hook-utils.sh and is called by all 3 delivery hooks
- ~90 lines of triplicated delivery code removed from hook scripts
- ~28 lines of duplicated jq template removed from write_hook_event_record
- JSON injection bug eliminated (jq -cn --arg replaces echo with string interpolation)
- Stale comment deleted
- All modified files pass bash -n syntax validation
</success_criteria>

<output>
After completion, create `.planning/quick/12-fix-4-remaining-v3-1-retrospective-issue/12-SUMMARY.md`
</output>
