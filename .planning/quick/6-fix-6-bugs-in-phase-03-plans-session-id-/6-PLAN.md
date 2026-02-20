---
phase: quick-6
plan: "01"
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03-stop-event-full-stack/03-01-PLAN.md
  - .planning/phases/03-stop-event-full-stack/03-02-PLAN.md
  - .planning/phases/03-stop-event-full-stack/03-03-PLAN.md
autonomous: true
requirements:
  - BUG-1
  - BUG-2
  - BUG-3
  - BUG-4
  - BUG-5
  - BUG-6

must_haves:
  truths:
    - "No plan references extracting sessionName from the hook payload or stdin JSON"
    - "All plans resolve the tmux session name via execFileSync('tmux', ['display-message', '-p', '#S'])"
    - "03-03 Task 3 timeout values are in seconds (30, 30, 10) not milliseconds"
    - "03-03 context block references both 03-01-SUMMARY.md and 03-02-SUMMARY.md plus events/stop/prompt_stop.md"
    - "03-01 Task 1 does NOT mention Atomics.wait or SharedArrayBuffer"
    - "03-01 Task 2 verify step lists the 5 existing exports by name"
    - "03-03 Task 3 README examples use the nested settings.json format with seconds-based timeouts"
  artifacts:
    - path: ".planning/phases/03-stop-event-full-stack/03-01-PLAN.md"
      provides: "Fixed plan with tmux session resolution and simplified sleep"
    - path: ".planning/phases/03-stop-event-full-stack/03-02-PLAN.md"
      provides: "Fixed plan with tmux session resolution"
    - path: ".planning/phases/03-stop-event-full-stack/03-03-PLAN.md"
      provides: "Fixed plan with tmux session resolution, correct timeouts, nested format, and complete context refs"
  key_links: []
---

<objective>
Fix 6 bugs in the Phase 03 plan files (03-01, 03-02, 03-03) before execution begins. These are text edits to existing PLAN.md files — no code is created or executed.

Purpose: The plans contain incorrect assumptions about hook payload fields, wrong timeout units, missing context references, over-engineered sleep mechanisms, and wrong settings.json format. Executing them as-is would produce broken code.
Output: Three corrected PLAN.md files ready for execution.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/03-stop-event-full-stack/03-01-PLAN.md
@.planning/phases/03-stop-event-full-stack/03-02-PLAN.md
@.planning/phases/03-stop-event-full-stack/03-03-PLAN.md

# Reference for correct session resolution pattern
@bin/hook-event-logger.sh

# Reference for actual settings.json nested format and timeout units
# ~/.claude/settings.json uses nested format: "Stop": [{ "hooks": [{ "type": "command", ... }] }]
# Timeouts are in seconds (e.g., 10), NOT milliseconds (e.g., 10000)

# Reference for existing exports
@lib/index.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix BUG 1 (session resolution) + BUG 4 (sleep) + BUG 5 (export list) in 03-01-PLAN.md</name>
  <files>.planning/phases/03-stop-event-full-stack/03-01-PLAN.md</files>
  <action>
Read 03-01-PLAN.md and make these targeted edits:

**BUG 1 — Session resolution (Task 1 and Task 2):**
03-01-PLAN.md does not directly reference extracting sessionName from payload (its tasks create lib modules, not handlers). However, scan the entire file for any mention of "payload", "session_name", or "stdin JSON" extraction and replace with the tmux approach if found. The lib modules (tui-common.mjs and queue-processor.mjs) receive `sessionName` as a parameter — they do not extract it themselves. Confirm no changes needed for BUG 1 in this file. If the file is clean of payload extraction references, note this in the summary but make no BUG 1 changes to this file.

**BUG 4 — Simplify sleep mechanism (Task 1, lines ~94 and ~108-109):**
In Task 1's action section, find and remove:
- Line mentioning `Atomics.wait` on a `SharedArrayBuffer` for synchronous sleep (around line 94: "5. Add a small delay between send-keys calls using `Atomics.wait` on a `SharedArrayBuffer` (synchronous sleep without spawning a process — Node 22+ supports this). Use 100ms between keystrokes for tmux reliability.")
- The "Wait 100ms" instruction in the Tab-completion logic (around line 109)

Replace the removed sleep text with: "No explicit delay between send-keys calls. `execFileSync` blocks until tmux returns, which provides natural pacing. Only add delays if end-to-end testing shows timing issues."

Place this replacement text where the Atomics.wait paragraph was (step 5 area). Remove the "Wait 100ms" line from the Tab-completion steps entirely, so the Tab-completion flow is: type command name, send Tab, if arguments exist type space+arguments, send Enter.

**BUG 5 — List existing exports in verify step (Task 2, line ~179):**
In Task 2's verify section, the count "9 exports (5 existing + 4 new)" is correct. Expand it to list the 5 existing by name for executor reference:
Change: `must show 9 exports (5 existing + 4 new)`
To: `must show 9 exports (5 existing: appendJsonlEntry, extractJsonField, retryWithBackoff, resolveAgentFromSession, wakeAgentViaGateway + 4 new: typeCommandIntoTmuxSession, processQueueForHook, cancelQueueForSession, cleanupStaleQueueForSession)`
  </action>
  <verify>Read the modified 03-01-PLAN.md. Confirm: (1) no mention of "Atomics.wait" or "SharedArrayBuffer", (2) no "Wait 100ms" in Tab-completion steps, (3) the replacement text about execFileSync natural pacing is present, (4) verify step lists all 9 exports by name.</verify>
  <done>03-01-PLAN.md has simplified sleep (no Atomics.wait), and Task 2 verify lists all 9 exports by name for executor reference.</done>
</task>

<task type="auto">
  <name>Task 2: Fix BUG 1 (session resolution) in 03-02-PLAN.md and 03-03-PLAN.md</name>
  <files>.planning/phases/03-stop-event-full-stack/03-02-PLAN.md, .planning/phases/03-stop-event-full-stack/03-03-PLAN.md</files>
  <action>
**Fix 03-02-PLAN.md (Stop handler + TUI driver):**

In Task 1 (event_stop.mjs), find step 4 which says:
```
4. Extract `sessionName` from `hookPayload.session_name` (or the appropriate field name from Claude Code's Stop hook JSON — the session identifier)
```

Replace step 4 with:
```
4. **Resolve tmux session name** — Claude Code's hook JSON contains `session_id` (a UUID), NOT the tmux session name. The handler runs inside the tmux session, so get the session name the same way hook-event-logger.sh does (line 35):
   ```javascript
   import { execFileSync } from 'node:child_process';
   const tmuxSessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();
   ```
   If empty string (not running in tmux), exit 0 silently — this is an unmanaged session.
```

Also update the imports line at the bottom of Task 1's action to add `execFileSync` from `node:child_process` (if not already listed).

Scan the rest of 03-02-PLAN.md for any other references to extracting session name from the payload/stdin JSON and fix them similarly. The TUI driver (Task 2) receives `--session` as a CLI flag from the agent, so it does NOT need this fix — the agent already knows the session name from the event metadata.

**Fix 03-03-PLAN.md (SessionStart + UserPromptSubmit handlers):**

In Task 1 (event_session_start.mjs), find step 2 which says:
```
2. Extract `sessionName` from the payload (same field as Stop handler)
```

Replace step 2 with:
```
2. **Resolve tmux session name** — same approach as Stop handler (the hook JSON has `session_id` UUID, not the tmux name):
   ```javascript
   import { execFileSync } from 'node:child_process';
   const tmuxSessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();
   ```
   If empty string, exit 0 silently.
```

Update the imports line for Task 1 to include `execFileSync` from `node:child_process`.

In Task 2 (event_user_prompt_submit.mjs), find step 2 which says:
```
2. Extract `sessionName` from the payload
```

Replace step 2 with:
```
2. **Resolve tmux session name** — same approach as Stop and SessionStart handlers:
   ```javascript
   import { execFileSync } from 'node:child_process';
   const tmuxSessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();
   ```
   If empty string, exit 0 silently.
```

Update the imports line for Task 2 to include `execFileSync` from `node:child_process`.

In ALL three handler tasks across both files: replace subsequent references to `sessionName` variable with `tmuxSessionName` for consistency with the resolution code, OR keep `sessionName` but assign `const sessionName = tmuxSessionName;` right after resolution. Pick whichever reads cleaner — the key is that the variable is populated from tmux, not from the payload.
  </action>
  <verify>Search all three plan files for the phrase "from the payload" or "from hookPayload" relating to session name extraction. Must find zero matches. Search for "tmux display-message" — must find matches in 03-02 Task 1, 03-03 Task 1, and 03-03 Task 2 (3 total handler tasks). 03-02 Task 2 (TUI driver) should NOT have it (receives via --session flag).</verify>
  <done>All three event handler tasks (Stop, SessionStart, UserPromptSubmit) resolve tmux session name via execFileSync('tmux', ['display-message', '-p', '#S']) instead of extracting from hook payload. TUI driver unchanged (receives via --session CLI flag).</done>
</task>

<task type="auto">
  <name>Task 3: Fix BUG 2 (timeouts) + BUG 3 (context refs) + BUG 6 (settings format) in 03-03-PLAN.md</name>
  <files>.planning/phases/03-stop-event-full-stack/03-03-PLAN.md</files>
  <action>
**BUG 3 — Add missing context refs:**

In 03-03-PLAN.md's `<context>` block (around line 63-74), add these two references after the existing `03-01-SUMMARY.md` line:
```
@.planning/phases/03-stop-event-full-stack/03-02-SUMMARY.md
@events/stop/prompt_stop.md
```

The first is needed because 03-03 depends on 03-02 (both SessionStart and UserPromptSubmit handlers reference prompt_stop.md created in 03-02). The second is the actual prompt file both handlers import.

**BUG 2 — Fix timeout units in Task 3:**

In Task 3's action section, find all timeout values in the README template JSON examples and fix them from milliseconds to seconds:
- `"timeout": 30000` -> `"timeout": 30` (Stop and SessionStart hooks)
- `"timeout": 10000` -> `"timeout": 10` (UserPromptSubmit hook)

Also fix the "Notes to include" bullet that says "Timeouts are in milliseconds: Stop and SessionStart at 30000ms, UserPromptSubmit at 10000ms" to: "Timeouts are in seconds: Stop and SessionStart at 30, UserPromptSubmit at 10 (must be fast since it fires on every user input)"

**BUG 6 — Fix settings.json format in Task 3:**

The README template examples in Task 3 use a flat format:
```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "node /absolute/path/to/events/stop/event_stop.mjs",
        "timeout": 30000
      }
    ]
  }
}
```

Replace ALL three hook examples with the actual nested format from ~/.claude/settings.json:
```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "node /absolute/path/to/events/stop/event_stop.mjs",
        "timeout": 30
      }
    ]
  }
]
```

Apply the same nested pattern to SessionStart and UserPromptSubmit examples.

Also update the truth in the frontmatter `must_haves` that mentions timeouts. Change:
```
"README.md documents manual hook registration entries for settings.json: Stop (timeout 30), SessionStart (timeout 30), UserPromptSubmit (timeout 10)"
```
This is already correct (says 30 and 10 seconds). Keep it as-is.

Also update the `<done>` line for Task 3 — change any mention of millisecond values to second values.
  </action>
  <verify>Read the modified 03-03-PLAN.md. Confirm: (1) context block has both 03-01-SUMMARY.md and 03-02-SUMMARY.md plus events/stop/prompt_stop.md, (2) no "30000" or "10000" anywhere in the file, (3) README JSON examples use the nested format with inner "hooks" array wrapping each command object, (4) timeout values are 30 and 10 (seconds).</verify>
  <done>03-03-PLAN.md has complete context refs, seconds-based timeouts (30, 30, 10), and README examples match the actual nested settings.json format.</done>
</task>

</tasks>

<verification>
1. Search all three plan files for "Atomics.wait" or "SharedArrayBuffer" — zero matches
2. Search all three plan files for "from the payload" or "from hookPayload" relating to session name — zero matches
3. Search all three plan files for "tmux display-message" — 3 matches (one per handler task: 03-02 Task 1, 03-03 Task 1, 03-03 Task 2)
4. Search 03-03-PLAN.md for "30000" or "10000" — zero matches
5. 03-03-PLAN.md context block contains: 03-01-SUMMARY.md, 03-02-SUMMARY.md, prompt_stop.md
6. 03-03-PLAN.md README examples use nested format: `"hooks": [{ "type": "command", ... }]` inside each event array entry
7. 03-01-PLAN.md Task 2 verify step lists all 9 exports by name
</verification>

<success_criteria>
- All 6 bugs are fixed across the 3 plan files
- No plan tells the executor to extract session name from the hook payload
- All plans use the tmux display-message pattern for session resolution
- Timeout values in 03-03 are in seconds (30, 30, 10)
- 03-03 context block references both prior SUMMARY files and prompt_stop.md
- 03-01 sleep mechanism is simplified (no Atomics.wait)
- 03-03 README examples match actual nested settings.json format
</success_criteria>

<output>
After completion, create `.planning/quick/6-fix-6-bugs-in-phase-03-plans-session-id-/6-SUMMARY.md`
</output>
