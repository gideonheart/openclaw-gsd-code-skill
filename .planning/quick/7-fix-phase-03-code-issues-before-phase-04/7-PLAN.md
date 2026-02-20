---
phase: 7-fix-phase-03-code-issues-before-phase-04
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/queue-processor.mjs
  - lib/index.mjs
  - bin/tui-driver.mjs
  - events/stop/event_stop.mjs
  - events/session_start/event_session_start.mjs
  - events/user_prompt_submit/event_user_prompt_submit.mjs
  - events/stop/prompt_stop.md
autonomous: true
requirements: [DRY-01, SAFETY-01, PATH-01]

must_haves:
  truths:
    - "writeQueueFileAtomically and resolveQueueFilePath exist in exactly one place (lib/queue-processor.mjs)"
    - "All three event handlers survive malformed stdin without crashing (exit 0)"
    - "prompt_stop.md references tui-driver.mjs with an absolute path"
  artifacts:
    - path: "lib/queue-processor.mjs"
      provides: "writeQueueFileAtomically + resolveQueueFilePath as named exports"
      exports: ["writeQueueFileAtomically", "resolveQueueFilePath", "processQueueForHook", "cancelQueueForSession", "cleanupStaleQueueForSession"]
    - path: "lib/index.mjs"
      provides: "Barrel re-exports for writeQueueFileAtomically + resolveQueueFilePath"
      contains: "writeQueueFileAtomically"
    - path: "bin/tui-driver.mjs"
      provides: "Queue creation using imported shared functions (no local duplicates)"
    - path: "events/stop/prompt_stop.md"
      provides: "Absolute path to tui-driver.mjs"
      contains: "/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs"
  key_links:
    - from: "bin/tui-driver.mjs"
      to: "lib/queue-processor.mjs"
      via: "import from lib/index.mjs"
      pattern: "import.*writeQueueFileAtomically.*from"
---

<objective>
Fix 3 code quality issues from Phase 03 code review before starting Phase 04.

Purpose: Eliminate DRY violation, harden handlers against malformed stdin, fix incorrect relative path in prompt file.
Output: Clean, robust Phase 03 code ready for Phase 04 development.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@lib/queue-processor.mjs
@lib/index.mjs
@bin/tui-driver.mjs
@events/stop/event_stop.mjs
@events/session_start/event_session_start.mjs
@events/user_prompt_submit/event_user_prompt_submit.mjs
@events/stop/prompt_stop.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: De-duplicate writeQueueFileAtomically and resolveQueueFilePath</name>
  <files>lib/queue-processor.mjs, lib/index.mjs, bin/tui-driver.mjs</files>
  <action>
1. In `lib/queue-processor.mjs`: Add `export` keyword to both `writeQueueFileAtomically` (line 49) and `resolveQueueFilePath` (line 29) — they are currently private functions, make them named exports.

2. In `lib/index.mjs`: Add `writeQueueFileAtomically` and `resolveQueueFilePath` to the existing re-export line for queue-processor.mjs. The line currently reads:
   ```
   export { processQueueForHook, cancelQueueForSession, cleanupStaleQueueForSession } from './queue-processor.mjs';
   ```
   Update to:
   ```
   export { processQueueForHook, cancelQueueForSession, cleanupStaleQueueForSession, writeQueueFileAtomically, resolveQueueFilePath } from './queue-processor.mjs';
   ```

3. In `bin/tui-driver.mjs`:
   - Remove the local `writeQueueFileAtomically` function (lines 46-57 inclusive — the JSDoc + function body).
   - Remove the local `QUEUES_DIRECTORY` constant (line 30).
   - Remove unused imports that were only needed by the deleted code: `writeFileSync`, `renameSync`, `mkdirSync` from `node:fs`, and `dirname` from `node:path`. Keep `resolve` from `node:path` — it is still used on line 130 to build queueFilePath (but see next point).
   - Actually, with `resolveQueueFilePath` now imported, replace line 130 (`const queueFilePath = resolve(QUEUES_DIRECTORY, ...)`) with `const queueFilePath = resolveQueueFilePath(sessionName)` — this uses the shared function and eliminates the need for `resolve` from `node:path` entirely. Remove the `resolve` import too.
   - Add imports from `../lib/index.mjs`: `writeQueueFileAtomically` and `resolveQueueFilePath`. The existing import line for `typeCommandIntoTmuxSession` and `appendJsonlEntry` should be consolidated into a single import from `../lib/index.mjs`.
   - Keep `fileURLToPath` from `node:url` — it is used for `SKILL_ROOT` on line 29. Wait — `SKILL_ROOT` is only used by `QUEUES_DIRECTORY` which we are removing. Check: is `SKILL_ROOT` used anywhere else in tui-driver.mjs? No, it is not. Remove the `SKILL_ROOT` constant (line 29) and the `fileURLToPath` import from `node:url`. Also remove the `dirname` import since it was used for `SKILL_ROOT`.
   - Final state of imports in tui-driver.mjs should be:
     ```
     import { parseArgs } from 'node:util';
     import { writeQueueFileAtomically, resolveQueueFilePath, typeCommandIntoTmuxSession, appendJsonlEntry } from '../lib/index.mjs';
     ```
  </action>
  <verify>
Run `node --check bin/tui-driver.mjs` — must exit 0 (no syntax errors).
Run `node --check lib/queue-processor.mjs` — must exit 0.
Grep for `writeQueueFileAtomically` in bin/tui-driver.mjs — must appear only as import, never as function declaration.
Grep for `QUEUES_DIRECTORY` in bin/tui-driver.mjs — must not appear.
Grep for `SKILL_ROOT` in bin/tui-driver.mjs — must not appear.
  </verify>
  <done>writeQueueFileAtomically and resolveQueueFilePath exist only in lib/queue-processor.mjs, are exported via lib/index.mjs, and bin/tui-driver.mjs imports and uses them with no local duplicates or unused imports.</done>
</task>

<task type="auto">
  <name>Task 2: Guard JSON.parse in all event handlers against malformed stdin</name>
  <files>events/stop/event_stop.mjs, events/session_start/event_session_start.mjs, events/user_prompt_submit/event_user_prompt_submit.mjs</files>
  <action>
In each of the three event handler files, wrap the `JSON.parse(rawStdin)` call in a try/catch block. On parse failure, exit 0 silently (hook handlers must never crash on bad input).

Pattern to apply in all three files — replace:
```js
const hookPayload = JSON.parse(rawStdin);
```
with:
```js
let hookPayload;
try {
  hookPayload = JSON.parse(rawStdin);
} catch {
  process.exit(0);
}
```

Specific locations:
- `events/stop/event_stop.mjs` line 29: `const hookPayload = JSON.parse(rawStdin);`
- `events/session_start/event_session_start.mjs` line 30: `const hookPayload = JSON.parse(rawStdin);`
- `events/user_prompt_submit/event_user_prompt_submit.mjs` line 26: The bare `JSON.parse(rawStdin);` — this one does not even assign the result. Wrap it the same way, but since the result is unused, just do:
  ```js
  try {
    JSON.parse(rawStdin);
  } catch {
    process.exit(0);
  }
  ```

Do NOT change anything else in these files. The rest of the handler logic stays exactly as-is.
  </action>
  <verify>
Run `node --check events/stop/event_stop.mjs` — must exit 0.
Run `node --check events/session_start/event_session_start.mjs` — must exit 0.
Run `node --check events/user_prompt_submit/event_user_prompt_submit.mjs` — must exit 0.
Grep for unguarded `JSON.parse` in all three files — the only JSON.parse calls should be inside try blocks.
  </verify>
  <done>All three event handlers survive malformed stdin by catching JSON.parse errors and exiting 0 instead of crashing with exit 1.</done>
</task>

<task type="auto">
  <name>Task 3: Fix relative path in prompt_stop.md to absolute path</name>
  <files>events/stop/prompt_stop.md</files>
  <action>
In `events/stop/prompt_stop.md`, line 16, replace the relative path:
```
node bin/tui-driver.mjs --session <session-name> '["/clear", "/gsd:plan-phase 3"]'
```
with the absolute path:
```
node /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs --session <session-name> '["/clear", "/gsd:plan-phase 3"]'
```

This is a prompt file read by the orchestrating agent (Gideon) who runs from the OpenClaw workspace root, NOT from the gsd-code-skill directory. The absolute path ensures the command works regardless of working directory.

Do NOT change anything else in the file.
  </action>
  <verify>
Grep prompt_stop.md for the string `/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs` — must match exactly once.
Grep prompt_stop.md for the string `node bin/tui-driver.mjs` (without absolute path) — must NOT match.
  </verify>
  <done>prompt_stop.md uses the absolute path to tui-driver.mjs so the command works from any working directory.</done>
</task>

</tasks>

<verification>
1. `node --check bin/tui-driver.mjs && node --check lib/queue-processor.mjs && echo "Syntax OK"` — both pass
2. `node --check events/stop/event_stop.mjs && node --check events/session_start/event_session_start.mjs && node --check events/user_prompt_submit/event_user_prompt_submit.mjs && echo "All handlers OK"` — all three pass
3. No duplicate `writeQueueFileAtomically` function definitions exist outside lib/queue-processor.mjs
4. No unguarded `JSON.parse` exists in event handler files
5. No relative `bin/tui-driver.mjs` path exists in prompt_stop.md
</verification>

<success_criteria>
- DRY: writeQueueFileAtomically defined once in lib/queue-processor.mjs, exported via lib/index.mjs, imported by bin/tui-driver.mjs
- Safety: All 3 event handlers catch JSON.parse failures and exit 0
- Path: prompt_stop.md uses absolute path /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs
- All modified files pass node --check syntax validation
</success_criteria>

<output>
After completion, create `.planning/quick/7-fix-phase-03-code-issues-before-phase-04/7-01-SUMMARY.md`
</output>
