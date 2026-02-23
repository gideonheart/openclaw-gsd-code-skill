---
phase: quick-25
plan: 25
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/tui-common.mjs
  - bin/tui-driver-ask.mjs
autonomous: true
requirements: [QUICK-25]

must_haves:
  truths:
    - "Queue commands with arguments (e.g. /gsd:research-phase 18) arrive in Claude Code with exactly one space before the argument, not two"
    - "AskUserQuestion TUI keystrokes only fire after the TUI is actually rendered in the tmux pane"
  artifacts:
    - path: "lib/tui-common.mjs"
      provides: "Tab autocomplete command typing without double-space, captureTmuxPaneContent utility"
      exports: ["typeCommandIntoTmuxSession", "sendKeysToTmux", "sendSpecialKeyToTmux", "sleepMilliseconds", "captureTmuxPaneContent"]
    - path: "bin/tui-driver-ask.mjs"
      provides: "AskUserQuestion TUI driver that polls for TUI visibility before sending keystrokes"
      contains: "waitForTuiContentToAppear"
  key_links:
    - from: "lib/tui-common.mjs"
      to: "tmux send-keys"
      via: "execFileSync argument array"
      pattern: "sendKeysToTmux.*commandArguments"
    - from: "bin/tui-driver-ask.mjs"
      to: "lib/tui-common.mjs"
      via: "captureTmuxPaneContent import"
      pattern: "captureTmuxPaneContent"
---

<objective>
Fix two TUI driver bugs that prevent the agent from reliably controlling Claude Code sessions:

1. Queue command arguments lost due to double-space after Tab autocomplete
2. AskUserQuestion keystrokes sent before the TUI renders (fixed delay insufficient)

Purpose: Without these fixes, the orchestrating agent cannot pass arguments to GSD slash commands or reliably answer AskUserQuestion prompts — both are critical for autonomous session control.
Output: Patched lib/tui-common.mjs and bin/tui-driver-ask.mjs
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@lib/tui-common.mjs
@bin/tui-driver-ask.mjs
@lib/queue-processor.mjs (lines 228-229 confirm Tab autocomplete trailing space behavior)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix double-space in typeGsdCommandWithTabCompletion and add captureTmuxPaneContent</name>
  <files>lib/tui-common.mjs</files>
  <action>
Two changes to lib/tui-common.mjs:

**Fix 1 — Remove leading space before arguments (line 85):**

In `typeGsdCommandWithTabCompletion()`, change line 85 from:
```javascript
sendKeysToTmux(tmuxSessionName, ' ' + commandArguments);
```
to:
```javascript
sendKeysToTmux(tmuxSessionName, commandArguments);
```

Reason: Tab autocomplete already appends a trailing space (confirmed by isPromptFromTuiDriver comment at queue-processor.mjs line 228-229). The leading space in the current code creates a double-space, which causes Claude Code to drop the argument entirely.

**Fix 2 — Add captureTmuxPaneContent() export:**

Add a new exported function `captureTmuxPaneContent(tmuxSessionName)` that runs `tmux capture-pane -t <session> -p` via `execFileSync` and returns the pane content as a trimmed string. This is needed by tui-driver-ask.mjs (Task 2) to poll for TUI visibility.

Implementation:
- Use `execFileSync('tmux', ['capture-pane', '-t', tmuxSessionName, '-p'], { encoding: 'utf8' })`
- Return `.trim()` result
- Add JSDoc: captures current visible content of the tmux pane for polling/assertion purposes

NOTE: This is NOT pane scraping for content extraction (which PROJECT.md explicitly bans). This is TUI readiness detection — checking whether the AskUserQuestion prompt has rendered before sending keystrokes. The distinction: we are reading UI state to time keystrokes, not extracting message content.
  </action>
  <verify>
    <automated>node -e "import { captureTmuxPaneContent } from './lib/tui-common.mjs'; console.log(typeof captureTmuxPaneContent)" 2>&1 | grep -q "function" && echo "PASS: captureTmuxPaneContent exported" || echo "FAIL"; grep -c "' ' + commandArguments" lib/tui-common.mjs | grep -q "0" && echo "PASS: double-space removed" || echo "FAIL: double-space still present"</automated>
  </verify>
  <done>typeGsdCommandWithTabCompletion sends arguments without leading space. captureTmuxPaneContent is exported and callable.</done>
</task>

<task type="auto">
  <name>Task 2: Replace fixed delay with tmux pane polling in tui-driver-ask.mjs</name>
  <files>bin/tui-driver-ask.mjs</files>
  <action>
Replace the unreliable fixed `PRE_KEYSTROKE_DELAY_MILLISECONDS = 3000` sleep with a polling loop that waits for the AskUserQuestion TUI to actually appear in the tmux pane.

**Step 1 — Add import:**
Add `captureTmuxPaneContent` to the import from `../lib/tui-common.mjs`.

**Step 2 — Add waitForTuiContentToAppear() function:**

Create a new function `waitForTuiContentToAppear(sessionName, questionMetadata)` that:
- Defines `POLL_INTERVAL_MILLISECONDS = 250` and `MAXIMUM_WAIT_MILLISECONDS = 15000` as local constants
- Extracts a search string from `questionMetadata.questions[0]` — use the first question's title/text (the `.question` field from the saved metadata). This is the text that will appear in the pane when the TUI renders.
- In a loop: calls `captureTmuxPaneContent(sessionName)`, checks if the pane content `.includes(searchString)`, returns if found
- If `MAXIMUM_WAIT_MILLISECONDS` exceeded without finding the content, log a warning via `appendJsonlEntry` (level: 'warn', message about TUI not detected within timeout) and proceed anyway (do not throw — better to attempt keystrokes than abort entirely)
- Uses `sleepMilliseconds(POLL_INTERVAL_MILLISECONDS)` between polls
- Wrap each `captureTmuxPaneContent` call in try/catch — if tmux capture fails (e.g. session gone), break out of the loop and proceed

**Step 3 — Replace sleep call:**
Replace line 301 `sleepMilliseconds(PRE_KEYSTROKE_DELAY_MILLISECONDS);` with `waitForTuiContentToAppear(sessionName, questionMetadata);`

**Step 4 — Remove the stale constant:**
Remove the `PRE_KEYSTROKE_DELAY_MILLISECONDS = 3000` constant declaration and its JSDoc comment block (lines 47-54). It is no longer used.

**Step 5 — Update module-level JSDoc:**
Update the header comment block (lines 31-39) to replace the description of the fixed delay approach with a brief note about tmux pane polling. Remove the paragraph about "PRE_KEYSTROKE_DELAY_MILLISECONDS" and replace with: "Uses tmux pane polling (captureTmuxPaneContent) to detect when the AskUserQuestion TUI has rendered before sending keystrokes."
  </action>
  <verify>
    <automated>grep -q "waitForTuiContentToAppear" bin/tui-driver-ask.mjs && echo "PASS: polling function exists" || echo "FAIL"; grep -q "PRE_KEYSTROKE_DELAY_MILLISECONDS" bin/tui-driver-ask.mjs && echo "FAIL: stale constant still present" || echo "PASS: stale constant removed"; grep -q "captureTmuxPaneContent" bin/tui-driver-ask.mjs && echo "PASS: captureTmuxPaneContent imported" || echo "FAIL"</automated>
  </verify>
  <done>tui-driver-ask.mjs polls tmux pane for question text visibility before sending keystrokes. Fixed delay constant removed. Timeout fallback ensures keystrokes are attempted even if polling fails.</done>
</task>

</tasks>

<verification>
Both files parse without syntax errors:
```bash
node --check lib/tui-common.mjs && node --check bin/tui-driver-ask.mjs
```

No remaining double-space pattern:
```bash
grep "' ' + commandArguments" lib/tui-common.mjs  # Should return nothing
```

No remaining fixed delay constant:
```bash
grep "PRE_KEYSTROKE_DELAY_MILLISECONDS" bin/tui-driver-ask.mjs  # Should return nothing
```

New exports available:
```bash
node -e "import('./lib/tui-common.mjs').then(m => console.log(Object.keys(m).sort().join(', ')))"
# Should include: captureTmuxPaneContent, sendKeysToTmux, sendSpecialKeyToTmux, sleepMilliseconds, typeCommandIntoTmuxSession
```
</verification>

<success_criteria>
1. typeGsdCommandWithTabCompletion types arguments without a leading space — Tab autocomplete trailing space is the only separator
2. tui-driver-ask.mjs polls tmux pane content for question text before sending keystrokes instead of using a fixed 3s delay
3. Polling has a 15s maximum timeout with graceful fallback (warn + proceed)
4. Both files pass node --check syntax validation
5. captureTmuxPaneContent is exported from lib/tui-common.mjs
</success_criteria>

<output>
After completion, create `.planning/quick/25-fix-tui-driver-queue-command-args-lost-a/25-SUMMARY.md`
</output>
