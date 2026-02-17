---
phase: quick-3
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/menu-driver.sh
  - scripts/spawn.sh
autonomous: true
requirements: []
must_haves:
  truths:
    - "menu-driver.sh type action submits text after typing it (Tab+Enter, not just Enter)"
    - "spawn.sh waits for Claude TUI to be ready before sending the first command"
    - "Existing menu-driver.sh actions (choose, enter, esc, clear_then, submit, snapshot) are unchanged"
  artifacts:
    - path: "scripts/menu-driver.sh"
      provides: "type action with proper submission via Tab+Enter"
      contains: "Tab Enter"
    - path: "scripts/spawn.sh"
      provides: "Robust TUI readiness detection before sending first command"
      contains: "capture-pane"
  key_links:
    - from: "scripts/menu-driver.sh (type action)"
      to: "Claude Code AskUserQuestion TUI"
      via: "tmux send-keys Tab Enter (submit form)"
      pattern: "send-keys.*Tab.*Enter"
---

<objective>
Fix bug where agent types a value into Claude Code's AskUserQuestion TUI prompt but the value is never submitted.

Purpose: Two related issues prevent autonomous agent interaction with Claude Code TUI:
1. menu-driver.sh `type` action sends `Enter` after typing, but in Claude Code's AskUserQuestion form, Enter inserts a newline rather than submitting. The form requires Tab (to focus Submit button) + Enter (to activate it).
2. spawn.sh uses a fixed `sleep 1` before sending the first command, but Claude Code TUI takes 3-8 seconds to initialize, causing the command to be sent before the input is ready.

Output: Fixed menu-driver.sh and spawn.sh with proper TUI interaction patterns.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@scripts/menu-driver.sh
@scripts/spawn.sh
@scripts/recover-openclaw-agents.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix menu-driver.sh type action to submit after typing</name>
  <files>scripts/menu-driver.sh</files>
  <action>
In scripts/menu-driver.sh, modify the `type` action (currently lines 58-64) to submit the form after typing text.

Current behavior (BROKEN):
```bash
type)
    text="$*"
    [ -n "$text" ] || { echo "type requires text argument" >&2; usage; exit 1; }
    tmux send-keys -t "$SESSION:0.0" C-u
    tmux send-keys -t "$SESSION:0.0" -l -- "$text"
    tmux send-keys -t "$SESSION:0.0" Enter
    ;;
```

The problem: In Claude Code's AskUserQuestion TUI form, `Enter` inserts a newline inside the text area. It does NOT submit the form. To submit, you must press Tab (moves focus to the Submit button) then Enter (activates it).

Fix: Replace the final `Enter` with `Tab Enter` to properly submit the form. Add a small sleep (0.05s) between the text send and Tab to ensure the TUI registers the text before focus change.

New behavior:
```bash
type)
    text="$*"
    [ -n "$text" ] || { echo "type requires text argument" >&2; usage; exit 1; }
    tmux send-keys -t "$SESSION:0.0" C-u
    tmux send-keys -t "$SESSION:0.0" -l -- "$text"
    sleep 0.05
    tmux send-keys -t "$SESSION:0.0" Tab Enter
    ;;
```

Do NOT change any other actions in menu-driver.sh. The `submit` action (Tab Enter) remains as a separate action for standalone use. The `enter` action remains unchanged for cases where a plain Enter is needed.
  </action>
  <verify>
Run: `bash -n scripts/menu-driver.sh` to verify no syntax errors.
Run: `grep -A5 'type)' scripts/menu-driver.sh` to confirm the type action now uses Tab Enter instead of just Enter.
  </verify>
  <done>
menu-driver.sh type action sends literal text then submits the form via Tab+Enter. The text area content is submitted to Claude Code instead of having a newline appended.
  </done>
</task>

<task type="auto">
  <name>Task 2: Fix spawn.sh to wait for TUI readiness before sending first command</name>
  <files>scripts/spawn.sh</files>
  <action>
In scripts/spawn.sh, replace the fixed `sleep 1` (line 378) with a polling loop that waits for the Claude Code TUI to be ready before sending the first command.

Current behavior (UNRELIABLE):
```bash
# Wait for TUI startup
sleep 1

# Send first command
log "First command => $first_command"
tmux send-keys -t "${actual_session_name}:0.0" -l -- "$first_command"
tmux send-keys -t "${actual_session_name}:0.0" Enter
```

The problem: Claude Code TUI takes 3-8 seconds to initialize. A fixed 1-second sleep is insufficient. The first command arrives before the TUI input is ready, causing it to be lost or garbled.

Fix: Replace `sleep 1` with a readiness polling loop. Poll `tmux capture-pane` for Claude Code TUI indicators (same patterns used in recover-openclaw-agents.sh). Maximum wait: 15 seconds. Poll interval: 0.5 seconds.

Create a new function `wait_for_claude_tui_readiness` that:
1. Loops up to 30 iterations (15 seconds total at 0.5s intervals)
2. Captures pane content via `tmux capture-pane -pt "${session_name}:0.0" -S -30`
3. Checks for TUI readiness patterns: `What can I help|Claude Code|>.*$` (the prompt indicator)
4. Returns 0 (success) when TUI is detected, 1 (failure) after timeout
5. Logs progress every 5 seconds

Replace the `sleep 1` block (lines 377-383) with:
```bash
# Wait for TUI startup (poll for readiness instead of fixed sleep)
if wait_for_claude_tui_readiness "${actual_session_name}"; then
  log "TUI ready, sending first command"
else
  log "WARN: TUI readiness not confirmed after 15s, sending first command anyway"
fi

# Send first command
log "First command => $first_command"
tmux send-keys -t "${actual_session_name}:0.0" -l -- "$first_command"
tmux send-keys -t "${actual_session_name}:0.0" Enter
```

Place the `wait_for_claude_tui_readiness` function before `main()`, after `start_tmux_server_if_needed()`.

Function implementation:
```bash
wait_for_claude_tui_readiness() {
  local session_name="$1"
  local max_attempts=30
  local attempt=0

  while [ "$attempt" -lt "$max_attempts" ]; do
    local pane_content
    pane_content="$(tmux capture-pane -pt "${session_name}:0.0" -S -30 2>/dev/null || echo "")"

    if echo "$pane_content" | grep -Eiq 'What can I help|Claude Code|tips for|/help'; then
      return 0
    fi

    attempt=$((attempt + 1))
    if [ $((attempt % 10)) -eq 0 ]; then
      log "Waiting for Claude TUI... (${attempt}/${max_attempts})"
    fi
    sleep 0.5
  done

  return 1
}
```

The detection patterns match what the TUI displays when fully initialized:
- "What can I help" - the main prompt greeting
- "Claude Code" - header text visible during startup
- "tips for" - part of the "tips for getting started" help text
- "/help" - visible in the initial help text

Do NOT change any other logic in spawn.sh. The function follows the same pattern as `ensure_claude_is_running_in_tmux` in recover-openclaw-agents.sh.
  </action>
  <verify>
Run: `bash -n scripts/spawn.sh` to verify no syntax errors.
Run: `grep -c 'wait_for_claude_tui_readiness' scripts/spawn.sh` to confirm function exists and is called (should return 2+: definition and call).
Run: `grep 'sleep 1' scripts/spawn.sh` to confirm the old fixed sleep is removed (should return no matches near "TUI startup").
  </verify>
  <done>
spawn.sh polls for Claude Code TUI readiness (up to 15 seconds) before sending the first command, instead of using a fixed 1-second sleep. Falls back gracefully if readiness detection times out.
  </done>
</task>

</tasks>

<verification>
1. `bash -n scripts/menu-driver.sh && bash -n scripts/spawn.sh` -- both scripts pass syntax check
2. `grep -A5 'type)' scripts/menu-driver.sh` -- type action ends with Tab Enter, not just Enter
3. `grep 'wait_for_claude_tui_readiness' scripts/spawn.sh` -- readiness function exists and is used
4. `grep -c 'sleep 1' scripts/spawn.sh` -- no "sleep 1" for TUI wait (may still exist elsewhere, but not for TUI startup)
5. All other menu-driver.sh actions remain unchanged (choose, enter, esc, clear_then, submit, snapshot)
</verification>

<success_criteria>
- menu-driver.sh type action types text AND submits the form (Tab+Enter pattern)
- spawn.sh waits for Claude TUI readiness via polling before sending first command
- Both scripts pass bash -n syntax validation
- No regressions to other menu-driver.sh actions or spawn.sh functionality
</success_criteria>

<output>
After completion, create `.planning/quick/3-fix-bug-where-agent-types-command-in-tui/3-SUMMARY.md`
</output>
