---
phase: quick-16
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/hook-event-logger.sh
  - scripts/register-all-hooks-logger.sh
autonomous: true
requirements: [QUICK-16]

must_haves:
  truths:
    - "All 15 Claude Code hook events are registered in ~/.claude/settings.json"
    - "Each hook event fires the logger and raw stdin JSON is captured to per-session log"
    - "Existing GSD hook registrations are preserved (additive, not replacing)"
    - "All current log files in logs/ are cleared before use"
  artifacts:
    - path: "scripts/hook-event-logger.sh"
      provides: "Universal hook event logger that reads stdin JSON and logs it"
      min_lines: 20
    - path: "scripts/register-all-hooks-logger.sh"
      provides: "Registration script that adds logger hooks for all 15 events to settings.json"
      min_lines: 40
  key_links:
    - from: "scripts/register-all-hooks-logger.sh"
      to: "~/.claude/settings.json"
      via: "jq merge adding logger entries to each hook event array"
      pattern: "jq.*hooks"
    - from: "~/.claude/settings.json hook entries"
      to: "scripts/hook-event-logger.sh"
      via: "command path in each hook registration"
      pattern: "hook-event-logger.sh"
    - from: "scripts/hook-event-logger.sh"
      to: "logs/{session}.log"
      via: "sources hook-preamble.sh, uses debug_log for per-session logging"
      pattern: "hook-preamble.sh"
---

<objective>
Create a debug hook event logger that registers ALL 15 Claude Code hook events and logs their raw stdin JSON payloads to per-session log files for analysis.

Purpose: Capture raw hook payload structures from a live session (warden-main-4) to understand what data each hook event provides, enabling future hook development.
Output: Two executable scripts — a universal logger and a registration script — plus cleared log directory.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@scripts/register-hooks.sh
@lib/hook-preamble.sh
@scripts/session-end-hook.sh
@~/.claude/settings.json
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create universal hook event logger script</name>
  <files>scripts/hook-event-logger.sh</files>
  <action>
Create `scripts/hook-event-logger.sh` — a single script that ALL 15 hook events can call to log raw stdin JSON.

The script must:
1. Start with `#!/usr/bin/env bash` and `set -euo pipefail`
2. Source the preamble: `source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/hook-preamble.sh"`
3. Immediately consume all stdin into a variable: `STDIN_JSON=$(cat)`
4. Record entry timestamp: `HOOK_ENTRY_MS=$(date +%s%3N)`
5. Extract `hook_event_name` from the JSON: `EVENT_NAME=$(printf '%s' "$STDIN_JSON" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)`
6. Log to global hooks.log via `debug_log`: the event name and byte count
7. Attempt tmux session detection: `SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")` — if empty, fall back to `SESSION_NAME="no-tmux"`
8. Redirect `GSD_HOOK_LOG` to per-session file: `GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"` (same pattern as existing hooks)
9. Log a structured entry to the per-session .log file containing:
   - Separator line: `===== HOOK EVENT: ${EVENT_NAME} =====`
   - Timestamp
   - Byte count of stdin
   - The FULL raw JSON pretty-printed: `printf '%s' "$STDIN_JSON" | jq '.' 2>/dev/null || printf '%s' "$STDIN_JSON"`
   - End separator
10. Also append a compact JSONL line to `${SKILL_LOG_DIR}/${SESSION_NAME}-raw-events.jsonl` using jq:
    ```
    jq -cn --arg event "$EVENT_NAME" --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" --argjson payload "$STDIN_JSON" '{timestamp: $timestamp, event: $event, payload: $payload}'
    ```
    Use flock for atomic append (same pattern as write_hook_event_record in hook-utils.sh).
    If STDIN_JSON is not valid JSON, fall back to storing it as a string with --arg instead of --argjson.
11. Exit 0 always (never crash Claude Code)

Key: This script does NOT do any registry lookup, wake message delivery, or state detection. It is purely a raw event logger. Wrap the entire body after preamble sourcing in a trap to ensure exit 0 on any error: `trap 'exit 0' ERR`

Make the file executable: `chmod +x scripts/hook-event-logger.sh`
  </action>
  <verify>
`bash -n scripts/hook-event-logger.sh` — syntax check passes.
`head -1 scripts/hook-event-logger.sh` outputs `#!/usr/bin/env bash`.
`test -x scripts/hook-event-logger.sh` — file is executable.
`grep -c 'hook-preamble.sh' scripts/hook-event-logger.sh` returns 1.
`grep -c 'STDIN_JSON' scripts/hook-event-logger.sh` returns at least 2 (assignment + usage).
  </verify>
  <done>
hook-event-logger.sh exists, is executable, passes syntax check, sources preamble, reads stdin, logs raw JSON to per-session .log and .jsonl files.
  </done>
</task>

<task type="auto">
  <name>Task 2: Create registration script and clear logs</name>
  <files>scripts/register-all-hooks-logger.sh</files>
  <action>
Create `scripts/register-all-hooks-logger.sh` that:

**Part A: Clear existing log files**
1. Remove all files in `logs/` directory: `rm -f "${SKILL_ROOT}/logs/"*.log "${SKILL_ROOT}/logs/"*.jsonl "${SKILL_ROOT}/logs/"*.lock "${SKILL_ROOT}/logs/"*.txt`
2. Log that logs were cleared

**Part B: Register logger hooks for all 15 events**

The critical design constraint: existing GSD hooks must be PRESERVED. The logger must be ADDED alongside existing hooks, not replace them.

Claude Code settings.json hook structure allows MULTIPLE entries per event. Each event is an array of rule objects. The strategy is:
- For events that already have GSD hooks (Stop, Notification, SessionEnd, PreCompact, PreToolUse, PostToolUse): APPEND a new rule object to the existing array
- For events with NO existing GSD hooks (SessionStart, Setup, UserPromptSubmit, PermissionRequest, PostToolUseFailure, SubagentStart, SubagentStop, TeammateIdle, TaskCompleted): CREATE a new array with just the logger

The script must:
1. Start with `#!/usr/bin/env bash` and `set -euo pipefail`
2. Resolve SKILL_ROOT: `SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"`
3. Define SETTINGS_FILE="$HOME/.claude/settings.json"
4. Define LOGGER_SCRIPT="${SKILL_ROOT}/scripts/hook-event-logger.sh"
5. Verify logger script exists
6. Backup settings.json (same pattern as register-hooks.sh)
7. Build a logger hook entry template — for most events, the rule object is:
   ```json
   {"hooks": [{"type": "command", "command": "/full/path/to/hook-event-logger.sh", "timeout": 10}]}
   ```
8. For the Notification event which uses matchers, add FOUR separate logger entries for the four subtypes (auth_success, permission_prompt, idle_prompt, elicitation_dialog) PLUS one catch-all without a matcher
9. For PreToolUse and PostToolUse, add one catch-all logger entry WITHOUT a matcher (existing GSD hooks use "AskUserQuestion" matcher — the logger catch-all will fire for ALL tool uses)

Use a single jq invocation that:
- Reads current settings
- For EACH of the 15 events, appends the logger rule to `.hooks.{EventName}` array (creating the array if it does not exist)
- Uses `(.hooks.EventName // []) + [$new_logger_rule]` pattern to preserve existing entries

All 15 event names to register (exact Claude Code event names):
SessionStart, Setup, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, PreCompact, SessionEnd

After jq merge: validate JSON, atomic replace (mv .tmp over original), same pattern as register-hooks.sh.

Print verification summary showing all registered hooks per event, highlighting which are "GSD" vs "logger".

Make the file executable: `chmod +x scripts/register-all-hooks-logger.sh`
  </action>
  <verify>
`bash -n scripts/register-all-hooks-logger.sh` — syntax check passes.
`test -x scripts/register-all-hooks-logger.sh` — file is executable.
Run the script: `bash scripts/register-all-hooks-logger.sh`
Then verify:
- `ls logs/` shows empty directory (logs cleared)
- `jq '.hooks | keys' ~/.claude/settings.json` shows all 15 event types
- `jq '.hooks.SessionStart | length' ~/.claude/settings.json` shows at least 2 (existing gsd-check-update.js + new logger)
- `jq '.hooks.Stop | length' ~/.claude/settings.json` shows at least 2 (existing stop-hook.sh + new logger)
- `jq '.hooks.SubagentStart | length' ~/.claude/settings.json` shows at least 1 (new logger — no prior GSD hook)
- `jq '.hooks.Notification | length' ~/.claude/settings.json` shows more entries than before (existing 2 matchers + new logger entries)
- All logger entries point to the correct absolute path for hook-event-logger.sh
  </verify>
  <done>
register-all-hooks-logger.sh exists, is executable, and when run: clears all log files, adds logger hook registrations for all 15 events in settings.json while preserving all existing GSD hook registrations. Verification shows all 15 event types present with logger entries alongside existing hooks.
  </done>
</task>

</tasks>

<verification>
1. `bash -n scripts/hook-event-logger.sh && bash -n scripts/register-all-hooks-logger.sh` — both pass syntax check
2. `bash scripts/register-all-hooks-logger.sh` — runs without errors, shows summary
3. `ls logs/` — empty (cleared)
4. `jq '.hooks | keys | length' ~/.claude/settings.json` — returns 15
5. `jq '[.hooks[][] | select(.hooks[].command | contains("hook-event-logger.sh"))] | length' ~/.claude/settings.json` — shows logger registered across all events
6. `jq '.hooks.Stop[].hooks[].command' ~/.claude/settings.json` — shows BOTH stop-hook.sh AND hook-event-logger.sh (additive proof)
</verification>

<success_criteria>
- Both scripts exist, are executable, pass bash -n syntax check
- Running register-all-hooks-logger.sh clears logs/ and registers logger for all 15 events
- Existing GSD hooks (Stop, Notification x2, SessionEnd, PreCompact, PreToolUse, PostToolUse, SessionStart) are all still present in settings.json
- Logger hooks are added alongside existing hooks, not replacing them
- hook-event-logger.sh sources preamble, reads stdin, logs raw JSON to per-session files
- Ready for user to trigger hooks in warden-main-4 session and inspect logged payloads
</success_criteria>

<output>
After completion, create `.planning/quick/16-create-hook-event-logger-script-for-all-/16-SUMMARY.md`
</output>
