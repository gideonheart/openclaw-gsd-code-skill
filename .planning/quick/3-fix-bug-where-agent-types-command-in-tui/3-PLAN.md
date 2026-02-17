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
    - "menu-driver.sh type action submits text by pressing Tab then Enter (same as submit action), not just Enter"
    - "spawn.sh polls for Claude TUI readiness via capture-pane before sending first command instead of fixed sleep"
    - "Existing menu-driver.sh actions (choose, enter, esc, clear_then, submit, snapshot) are unchanged"
  artifacts:
    - path: "scripts/menu-driver.sh"
      provides: "type action with Tab+Enter form submission"
      contains: "Tab Enter"
    - path: "scripts/spawn.sh"
      provides: "TUI readiness polling via capture-pane before first command"
      contains: "capture-pane"
  key_links:
    - from: "scripts/menu-driver.sh (type action)"
      to: "Claude Code AskUserQuestion TUI"
      via: "tmux send-keys Tab Enter to submit the form"
      pattern: "send-keys.*Tab.*Enter"
    - from: "scripts/spawn.sh (wait_for_claude_tui_readiness)"
      to: "Claude Code TUI startup"
      via: "tmux capture-pane polling loop"
      pattern: "capture-pane"
---

<objective>
Fix bug where agent types a value into Claude Code's AskUserQuestion TUI prompt but the value is never submitted.

Purpose: Two related issues prevent autonomous agent interaction with Claude Code TUI:
1. menu-driver.sh `type` action sends `Enter` after typing text, but Claude Code's AskUserQuestion form treats Enter as "insert newline" not "submit form". Submission requires Tab (focus Submit button) then Enter (activate it) -- exactly what the existing `submit` action already does.
2. spawn.sh uses a fixed `sleep 1` before sending the first command, but Claude Code TUI takes 3-8 seconds to initialize. The first command arrives before input is ready and gets lost.

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
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix menu-driver.sh type action to submit form after typing</name>
  <files>scripts/menu-driver.sh</files>
  <action>
In scripts/menu-driver.sh, modify the `type` action case block (lines 58-64).

The root cause: Claude Code's AskUserQuestion TUI has a multi-line text input area. Pressing Enter inserts a newline inside the text area. It does NOT submit the form. To submit the form, you must press Tab (moves focus from text area to the Submit button) then Enter (activates the Submit button). The existing `submit` action (line 65-67) already does exactly this: `tmux send-keys -t "$SESSION:0.0" Tab Enter`.

Current (BROKEN) type action:
```bash
type)
    text="$*"
    [ -n "$text" ] || { echo "type requires text argument" >&2; usage; exit 1; }
    tmux send-keys -t "$SESSION:0.0" C-u
    tmux send-keys -t "$SESSION:0.0" -l -- "$text"
    tmux send-keys -t "$SESSION:0.0" Enter
    ;;
```

Change the final `Enter` line to use `Tab Enter` instead, with a small sleep (0.05s) between typing and Tab to ensure the TUI registers the typed text before focus changes:

Fixed type action:
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

Also update the usage text on line 15 to reflect the new behavior. Change:
  `type <text>                      Type literal freeform text + Enter`
to:
  `type <text>                      Type literal freeform text + submit (Tab Enter)`

Do NOT change any other actions. The `enter` action stays as-is (for cases where plain Enter is needed). The `submit` action stays as-is (for standalone form submission without typing).
  </action>
  <verify>
Run: `bash -n scripts/menu-driver.sh` to confirm no syntax errors.
Run: `grep -A7 'type)' scripts/menu-driver.sh` to confirm the type action now uses `sleep 0.05` then `Tab Enter` instead of just `Enter`.
Run: `grep -c 'Tab Enter' scripts/menu-driver.sh` should return 2 (one in type action, one in submit action).
  </verify>
  <done>
menu-driver.sh type action types literal text then submits the form via Tab+Enter (same pattern as the submit action). The 0.05s sleep ensures text registration before focus change.
  </done>
</task>

<task type="auto">
  <name>Task 2: Fix spawn.sh to poll for TUI readiness before sending first command</name>
  <files>scripts/spawn.sh</files>
  <action>
In scripts/spawn.sh, replace the unreliable fixed `sleep 1` with a polling loop that waits for the Claude Code TUI to become ready.

The root cause: Claude Code TUI takes 3-8 seconds to initialize after launch. The current `sleep 1` (line 378) is too short, so the first command (e.g., `/gsd:resume-work`) arrives before the TUI input is ready and gets lost.

Step 1: Add a new function `wait_for_claude_tui_readiness` BEFORE the `main()` function (after `start_tmux_server_if_needed` around line 241). This follows the same detection pattern used in `ensure_claude_is_running_in_tmux` in recover-openclaw-agents.sh:

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

Detection patterns explained:
- "What can I help" -- the main prompt greeting when TUI is ready
- "Claude Code" -- header text visible during and after startup
- "tips for" -- part of "tips for getting started" help text
- "/help" -- visible in the initial help text

Step 2: Replace lines 377-383 (the sleep + send first command block) with:

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

This replaces the old `sleep 1` with up to 15 seconds of polling at 0.5s intervals, and falls back gracefully if readiness is not confirmed (sends the command anyway rather than failing).

Do NOT change any other logic in spawn.sh.
  </action>
  <verify>
Run: `bash -n scripts/spawn.sh` to confirm no syntax errors.
Run: `grep -c 'wait_for_claude_tui_readiness' scripts/spawn.sh` should return at least 2 (function definition + call site).
Run: `grep 'capture-pane' scripts/spawn.sh` to confirm polling uses tmux capture-pane.
Run: `grep -n 'sleep 1' scripts/spawn.sh` should NOT show a match near the "TUI startup" comment (the old fixed sleep is gone).
  </verify>
  <done>
spawn.sh polls for Claude Code TUI readiness via tmux capture-pane (up to 15 seconds at 0.5s intervals) before sending the first command. Falls back gracefully on timeout. The unreliable fixed `sleep 1` is removed.
  </done>
</task>

</tasks>

<verification>
1. `bash -n scripts/menu-driver.sh && bash -n scripts/spawn.sh` -- both pass syntax check
2. `grep -A7 'type)' scripts/menu-driver.sh` -- type action uses `sleep 0.05` then `Tab Enter`
3. `grep -c 'Tab Enter' scripts/menu-driver.sh` -- returns 2 (type action + submit action)
4. `grep -c 'wait_for_claude_tui_readiness' scripts/spawn.sh` -- returns 2+ (definition + usage)
5. `grep 'capture-pane' scripts/spawn.sh` -- readiness polling uses capture-pane
6. All other menu-driver.sh actions (choose, enter, esc, clear_then, submit, snapshot) remain unchanged
</verification>

<success_criteria>
- menu-driver.sh type action types text AND submits the form via Tab+Enter (not just Enter)
- spawn.sh waits for Claude TUI readiness via capture-pane polling before sending first command
- Both scripts pass bash -n syntax validation
- No regressions to other menu-driver.sh actions or spawn.sh functionality
</success_criteria>

<output>
After completion, create `.planning/quick/3-fix-bug-where-agent-types-command-in-tui/3-SUMMARY.md`
</output>
