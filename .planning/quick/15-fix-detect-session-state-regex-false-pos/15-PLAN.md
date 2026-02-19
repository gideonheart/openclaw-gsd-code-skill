---
phase: quick-15
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/hook-utils.sh
autonomous: true
requirements: [QUICK-15]

must_haves:
  truths:
    - "detect_session_state() returns 'working' when pane contains only the Claude Code status bar bypass text"
    - "detect_session_state() returns 'permission_prompt' only when an actual permission dialog is visible"
    - "detect_session_state() returns 'error' only when a genuine error state is visible, not for error-related words in conversation"
  artifacts:
    - path: "lib/hook-utils.sh"
      provides: "Fixed detect_session_state() function"
      contains: "bypass permissions|shift.tab to cycle"
  key_links:
    - from: "detect_session_state()"
      to: "scripts/stop-hook.sh, scripts/notification-idle-hook.sh, scripts/notification-permission-hook.sh, scripts/pre-compact-hook.sh"
      via: "sourced through hook-preamble.sh"
      pattern: "detect_session_state"
---

<objective>
Fix detect_session_state() in lib/hook-utils.sh to eliminate false positives caused by Claude Code's always-visible status bar text "bypass permissions on (shift+tab to cycle)".

Purpose: The status bar line matches the current 'permission|allow|dangerous' regex, causing 60% state misclassification — hooks report permission_prompt when the session is idle or working, producing wrong wake messages and misleading JSONL logs.

Output: Corrected detect_session_state() that strips status bar noise lines before matching, uses specific permission dialog patterns, and uses specific error patterns.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix detect_session_state() regex false positives</name>
  <files>lib/hook-utils.sh</files>
  <action>
Replace the detect_session_state() function body (lines 441-456) with a version that:

1. Strips status bar noise from pane_content before any matching. The Claude Code status bar always contains "bypass permissions on (shift+tab to cycle)" when skipDangerousModePermissionPrompt is true. Filter out lines matching this pattern using grep -v:
   ```bash
   local filtered_content
   filtered_content=$(printf '%s\n' "$pane_content" \
     | grep -Eiv 'bypass permissions|shift.tab to cycle' 2>/dev/null || true)
   ```

2. Use filtered_content for all subsequent regex checks (not pane_content).

3. Replace the permission_prompt pattern from `permission|allow|dangerous` with patterns that match actual Claude Code permission dialogs only:
   - `Do you want to allow`
   - `Allow this action`
   - `\(y/n\)` (the yes/no prompt Claude Code shows for tool confirmations)
   - `Approve|Deny` (the button labels shown in permission prompts)
   Pattern: `Do you want to allow|Allow this action|\(y/n\)|Approve|Deny`

4. Replace the error pattern from `error|failed|exception` (with post-pipe `grep -v 'error handling'`) with a more specific pattern that targets genuine error state indicators:
   - Leading `Error:` or `ERROR:` at line start
   - `Command failed` or `command not found`
   - `fatal:` (git errors)
   - `Traceback` (Python)
   Pattern (anchored or distinctive): `^Error:|^ERROR:|Command failed|command not found|fatal:|Traceback`
   Use `grep -Em` with the pattern so no second pipe is needed, cleaner implementation.

The final function should look like:
```bash
detect_session_state() {
  local pane_content="$1"

  local filtered_content
  filtered_content=$(printf '%s\n' "$pane_content" \
    | grep -Eiv 'bypass permissions|shift.tab to cycle' 2>/dev/null || true)

  if printf '%s\n' "$filtered_content" | grep -Eiq 'Enter to select|numbered.*option' 2>/dev/null; then
    printf 'menu'
  elif printf '%s\n' "$filtered_content" | grep -Eiq 'Do you want to allow|Allow this action|\(y/n\)|Approve|Deny' 2>/dev/null; then
    printf 'permission_prompt'
  elif printf '%s\n' "$filtered_content" | grep -Eiq 'What can I help|waiting for' 2>/dev/null; then
    printf 'idle'
  elif printf '%s\n' "$filtered_content" | grep -Eiq '^Error:|^ERROR:|Command failed|command not found|fatal:|Traceback' 2>/dev/null; then
    printf 'error'
  else
    printf 'working'
  fi
}
```

Also update the doc comment block above the function (lines 421-440) to reflect:
- The new status bar filtering step (mention it strips Claude Code status bar lines before matching)
- The more specific permission_prompt patterns
- The more specific error patterns
  </action>
  <verify>
Run the following inline tests against the updated function by sourcing lib/hook-utils.sh in a subshell:

```bash
cd /home/forge/.openclaw/workspace/skills/gsd-code-skill

source lib/hook-utils.sh

# Test 1: status bar only → should return 'working' (was returning 'permission_prompt')
result=$(detect_session_state "⏵⏵ bypass permissions on (shift+tab to cycle)")
[ "$result" = "working" ] && echo "PASS: status bar only → working" || echo "FAIL: got $result"

# Test 2: idle pane with status bar → should return 'idle'
result=$(detect_session_state "$(printf 'What can I help you with?\n⏵⏵ bypass permissions on (shift+tab to cycle)')")
[ "$result" = "idle" ] && echo "PASS: idle+statusbar → idle" || echo "FAIL: got $result"

# Test 3: real permission dialog → should return 'permission_prompt'
result=$(detect_session_state "Do you want to allow this tool to run?")
[ "$result" = "permission_prompt" ] && echo "PASS: permission dialog → permission_prompt" || echo "FAIL: got $result"

# Test 4: '7 tools allowed' should NOT trigger permission_prompt
result=$(detect_session_state "7 tools allowed for this session")
[ "$result" = "working" ] && echo "PASS: tools allowed → working" || echo "FAIL: got $result"

# Test 5: genuine error → should return 'error'
result=$(detect_session_state "Error: command not found: npx")
[ "$result" = "error" ] && echo "PASS: error line → error" || echo "FAIL: got $result"

# Test 6: error word in conversation → should NOT return 'error'
result=$(detect_session_state "The error handling in this code looks good")
[ "$result" = "working" ] && echo "PASS: error in text → working" || echo "FAIL: got $result"
```

All 6 tests must print PASS.
  </verify>
  <done>All 6 inline tests pass. The function no longer returns 'permission_prompt' for the Claude Code status bar. The 'allow' false positive from "N tools allowed" is eliminated. Generic error words in conversation do not trigger 'error' state.</done>
</task>

</tasks>

<verification>
Source lib/hook-utils.sh and run all 6 inline tests shown in the verify section. All must print PASS before the task is considered complete.
</verification>

<success_criteria>
- detect_session_state() returns 'working' when pane contains only the status bar bypass text
- detect_session_state() returns 'idle' when "What can I help" is present alongside the status bar
- detect_session_state() returns 'permission_prompt' only for genuine permission dialog text
- detect_session_state() does not misclassify "N tools allowed" as permission_prompt
- detect_session_state() returns 'error' for real error indicators (Error:, command not found, fatal:)
- detect_session_state() returns 'working' when error-related words appear in conversation prose
- Function doc comment updated to reflect the filtering step and new patterns
</success_criteria>

<output>
After completion, create `.planning/quick/15-fix-detect-session-state-regex-false-pos/15-SUMMARY.md` following the summary template.
</output>
