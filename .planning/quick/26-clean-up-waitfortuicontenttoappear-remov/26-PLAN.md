---
phase: quick-26
plan: 26
type: execute
wave: 1
depends_on: []
files_modified:
  - bin/tui-driver-ask.mjs
autonomous: true
requirements: []
must_haves:
  truths:
    - "waitForTuiContentToAppear is a synchronous function (no async keyword)"
    - "Success-path logs search string and elapsed milliseconds"
    - "Search strings over 60 characters trigger a warning log"
    - "Caught errors in the polling loop are logged, not silently swallowed"
    - "Timeout is 5 seconds, not 15 seconds"
    - "main() is not async and the call site has no await"
  artifacts:
    - path: "bin/tui-driver-ask.mjs"
      provides: "Cleaned up TUI driver for AskUserQuestion"
  key_links: []
---

<objective>
Clean up waitForTuiContentToAppear in bin/tui-driver-ask.mjs: remove unnecessary async/await, add observability (success-path logging, search string length guard, error logging in catch), and reduce timeout from 15s to 5s. Cascade the sync change to main() and its call site.

Purpose: The function uses only synchronous operations (sleepMilliseconds via Atomics.wait, captureTmuxPaneContent via execFileSync) but is marked async. The catch block silently swallows errors. Success path has no logging. The 15s timeout is excessive for a TUI that renders within 1-2 seconds.

Output: A cleaner, more observable bin/tui-driver-ask.mjs with no behavioral changes to the keystroke logic.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@bin/tui-driver-ask.mjs
@lib/tui-common.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Clean up waitForTuiContentToAppear and cascade sync to main()</name>
  <files>bin/tui-driver-ask.mjs</files>
  <action>
All changes are in bin/tui-driver-ask.mjs. Six modifications:

1. **Remove `async` from `waitForTuiContentToAppear`** (line 249). The function body uses only synchronous calls (`captureTmuxPaneContent`, `sleepMilliseconds`, `appendJsonlEntry`). No `async` needed.

2. **Reduce timeout from 15s to 5s.** Change `MAXIMUM_WAIT_MILLISECONDS` from `15000` to `5000`. Update the JSDoc comment on line 35 accordingly ("15s maximum timeout" -> "5s maximum timeout").

3. **Add search string length guard.** After the `searchString` assignment (line 256), add a guard: if `searchString.length > 60`, log a warning via `appendJsonlEntry` with level `warn`, source `tui-driver-ask`, a message explaining the search string may be too long for tmux pane line matching, and include the search string and its length. Do NOT abort -- this is advisory only, proceed with polling.

4. **Add success-path logging.** When `paneContent.includes(searchString)` is true (line 262), before returning, log via `appendJsonlEntry` with level `debug`, source `tui-driver-ask`, a message like `AskUserQuestion TUI detected in pane`, include `search_string`, and `elapsed_milliseconds` computed as `Date.now() - pollStartEpoch`. Then return.

5. **Log caught errors in catch block.** Replace the empty `catch {}` block (lines 265-268). Catch the error as `caughtError`, log via `appendJsonlEntry` with level `warn`, source `tui-driver-ask`, a message like `tmux capture-pane failed during TUI polling — proceeding with keystrokes`, include `error: caughtError.message` and `session: sessionName`. Then return (same behavior, just no longer silent).

6. **Cascade sync to main() and its call site:**
   - Remove `async` from `function main()` (line 282).
   - Remove `await` from `await waitForTuiContentToAppear(...)` call (line 329) -- just call it directly.
   - Replace the `main().catch(...)` pattern (lines 351-354) with:
     ```javascript
     try {
       main();
     } catch (caughtError) {
       process.stderr.write(`Error: ${caughtError.message}\n`);
       process.exit(1);
     }
     ```
     This is the correct pattern for a synchronous entry point.
  </action>
  <verify>
    <automated>node -c /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver-ask.mjs && node -e "import('/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver-ask.mjs').catch(() => {})" 2>&1 | head -5</automated>
    <manual>Verify: no `async` on waitForTuiContentToAppear or main, no `await` anywhere in file, timeout is 5000, catch block logs caughtError, success path logs elapsed_milliseconds, search string length guard at 60 chars</manual>
  </verify>
  <done>
    - waitForTuiContentToAppear has no `async` keyword
    - MAXIMUM_WAIT_MILLISECONDS is 5000
    - Search string length > 60 triggers a warn-level log
    - Successful TUI detection logs debug-level entry with search_string and elapsed_milliseconds
    - Catch block logs warn-level entry with error message (not silently swallowed)
    - main() has no `async` keyword
    - No `await` keyword appears anywhere in the file
    - Entry point uses try/catch around main() instead of .catch()
    - JSDoc header comment updated (15s -> 5s)
    - File parses without syntax errors
  </done>
</task>

</tasks>

<verification>
- `node -c bin/tui-driver-ask.mjs` passes (valid syntax)
- `grep -c 'async' bin/tui-driver-ask.mjs` returns 0 (no async anywhere)
- `grep -c 'await' bin/tui-driver-ask.mjs` returns 0 (no await anywhere)
- `grep 'MAXIMUM_WAIT_MILLISECONDS = 5000' bin/tui-driver-ask.mjs` matches
- `grep 'searchString.length > 60' bin/tui-driver-ask.mjs` matches
- `grep 'elapsed_milliseconds' bin/tui-driver-ask.mjs` matches
- `grep 'caughtError.message' bin/tui-driver-ask.mjs` matches (in catch block)
</verification>

<success_criteria>
bin/tui-driver-ask.mjs is fully synchronous, has proper observability logging on all code paths (success, timeout fallback, and error), guards against overly long search strings, and uses a 5s timeout instead of 15s.
</success_criteria>

<output>
After completion, create `.planning/quick/26-clean-up-waitfortuicontenttoappear-remov/26-SUMMARY.md`
</output>
