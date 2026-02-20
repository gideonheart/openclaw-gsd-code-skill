---
phase: quick-9
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/hook-context.mjs
  - lib/index.mjs
  - lib/tui-common.mjs
  - lib/queue-processor.mjs
  - bin/tui-driver.mjs
  - events/stop/event_stop.mjs
  - events/session_start/event_session_start.mjs
  - events/user_prompt_submit/event_user_prompt_submit.mjs
autonomous: true
requirements: [QT9-01, QT9-02, QT9-03, QT9-04, QT9-05, QT9-06]

must_haves:
  truths:
    - "Handler boilerplate (stdin read, JSON parse, tmux session, agent resolve) lives in exactly one place"
    - "Every guard-clause exit in every handler produces a debug-level JSONL entry"
    - "All wakeAgentViaGateway calls are wrapped in retryWithBackoff with 3 attempts / 2s base"
    - "sendKeysToTmux has no keyLiteralFlag parameter — empty string is hardcoded internally"
    - "promptFilePath in session_start and user_prompt_submit uses SKILL_ROOT, not ../stop/ navigation"
    - "tui-driver.mjs logs a warn JSONL entry when overwriting an existing queue file"
  artifacts:
    - path: "lib/hook-context.mjs"
      provides: "Shared readHookContext helper"
      exports: ["readHookContext"]
    - path: "lib/index.mjs"
      provides: "Re-exports readHookContext"
      contains: "readHookContext"
    - path: "lib/tui-common.mjs"
      provides: "Cleaned sendKeysToTmux API"
      contains: "function sendKeysToTmux(tmuxSessionName, textToType)"
    - path: "lib/queue-processor.mjs"
      provides: "Inline comment on in-place mutation safety"
      contains: "Claude Code fires events sequentially"
  key_links:
    - from: "events/stop/event_stop.mjs"
      to: "lib/hook-context.mjs"
      via: "import readHookContext"
      pattern: "readHookContext"
    - from: "events/session_start/event_session_start.mjs"
      to: "lib/hook-context.mjs"
      via: "import readHookContext"
      pattern: "readHookContext"
    - from: "events/user_prompt_submit/event_user_prompt_submit.mjs"
      to: "lib/hook-context.mjs"
      via: "import readHookContext"
      pattern: "readHookContext"
    - from: "events/stop/event_stop.mjs"
      to: "lib/retry.mjs"
      via: "retryWithBackoff wrapping wakeAgentViaGateway"
      pattern: "retryWithBackoff"
    - from: "events/session_start/event_session_start.mjs"
      to: "lib/paths.mjs"
      via: "SKILL_ROOT for promptFilePath"
      pattern: "SKILL_ROOT.*events.*stop.*prompt_stop"
---

<objective>
Fix all 6 Phase 03 code review findings from REVIEW.md Section 8 priorities.

Purpose: Eliminate DRY violation, improve operability (debug logging), add reliability (retry), clean APIs, and reduce fragile coupling before Phase 04 adds more handlers.
Output: 8 modified/created files implementing all 6 refactoring priorities.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/quick/8-analyse-phase-03-implementation-code-rev/REVIEW.md
@lib/tui-common.mjs
@lib/queue-processor.mjs
@lib/index.mjs
@lib/paths.mjs
@lib/retry.mjs
@lib/gateway.mjs
@bin/tui-driver.mjs
@events/stop/event_stop.mjs
@events/session_start/event_session_start.mjs
@events/user_prompt_submit/event_user_prompt_submit.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create readHookContext helper, fix sendKeysToTmux API, add queue-processor comment</name>
  <files>lib/hook-context.mjs, lib/index.mjs, lib/tui-common.mjs, lib/queue-processor.mjs</files>
  <action>
**1a. Create `lib/hook-context.mjs`** — new shared helper that extracts the duplicated handler boilerplate.

```javascript
/**
 * lib/hook-context.mjs — Shared hook handler context reader.
 *
 * Extracts the boilerplate shared by all event handlers: read stdin,
 * parse JSON payload, resolve tmux session name, resolve agent from registry.
 * Returns null (with debug log) if any step fails — caller exits 0.
 */

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolveAgentFromSession } from './agent-resolver.mjs';
import { appendJsonlEntry } from './logger.mjs';

/**
 * Read and validate the hook context from stdin + tmux environment.
 *
 * Reads raw stdin, parses as JSON, resolves the tmux session name via
 * `tmux display-message`, and resolves the agent from the session registry.
 * Logs a debug JSONL entry for each guard failure and returns null.
 *
 * @param {string} handlerSource - Handler name for log entries (e.g. 'event_stop').
 * @returns {{ hookPayload: Object, sessionName: string, resolvedAgent: Object }|null}
 *   The hook context object, or null if any guard check fails.
 */
export function readHookContext(handlerSource) {
  const rawStdin = readFileSync('/dev/stdin', 'utf8').trim();

  let hookPayload;
  try {
    hookPayload = JSON.parse(rawStdin);
  } catch {
    appendJsonlEntry({
      level: 'debug',
      source: handlerSource,
      message: 'Invalid JSON on stdin — skipping',
    });
    return null;
  }

  const sessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();

  if (!sessionName) {
    appendJsonlEntry({
      level: 'debug',
      source: handlerSource,
      message: 'No tmux session name — skipping',
    });
    return null;
  }

  const resolvedAgent = resolveAgentFromSession(sessionName);

  if (!resolvedAgent) {
    appendJsonlEntry({
      level: 'debug',
      source: handlerSource,
      message: 'Session not in agent registry — skipping',
      session: sessionName,
    });
    return null;
  }

  return { hookPayload, sessionName, resolvedAgent };
}
```

The function:
- Accepts `handlerSource` string for log attribution (e.g. `'event_stop'`)
- Returns `null` on any guard failure (malformed JSON, no session name, unmanaged session)
- Logs `debug`-level JSONL entry for every guard failure (Finding 3.2)
- Returns `{ hookPayload, sessionName, resolvedAgent }` on success
- Does NOT import from `./index.mjs` — imports directly from `./agent-resolver.mjs` and `./logger.mjs` to avoid circular dependency

**1b. Add re-export to `lib/index.mjs`**

Add this line to `lib/index.mjs`:
```javascript
export { readHookContext } from './hook-context.mjs';
```

**1c. Fix `sendKeysToTmux` in `lib/tui-common.mjs`** (Finding 3.5)

Remove `keyLiteralFlag` parameter. Change the function signature from:
```javascript
function sendKeysToTmux(tmuxSessionName, textToType, keyLiteralFlag) {
  execFileSync('tmux', ['send-keys', '-t', tmuxSessionName, textToType, keyLiteralFlag], {
```
to:
```javascript
function sendKeysToTmux(tmuxSessionName, textToType) {
  // Trailing empty string prevents tmux from interpreting textToType as a key name.
  // This is observed tmux 3.x behavior (not in manual) — consistent on Linux targets.
  execFileSync('tmux', ['send-keys', '-t', tmuxSessionName, textToType, ''], {
```

Update all internal call sites to remove the third `''` argument:
- Line 64: `sendKeysToTmux(tmuxSessionName, commandName);`
- Line 66: `sendKeysToTmux(tmuxSessionName, ' ' + commandArguments);`
- Line 68: `sendKeysToTmux(tmuxSessionName, commandText);`
- Line 82: `sendKeysToTmux(tmuxSessionName, commandText);`

Update the JSDoc to remove `@param {string} keyLiteralFlag`.

**1d. Add inline comment in `lib/queue-processor.mjs`** (Finding 3.4)

Before line 117 (`activeCommand.status = 'done';`), add:
```javascript
  // In-place mutation of the parsed JSON object. This is safe because Claude Code
  // fires events sequentially per session — no concurrent readers of queueData.
  // The mutated object is written atomically immediately after.
```

This is a comment-only change per the review verdict.
  </action>
  <verify>
Run `node -e "import('./lib/hook-context.mjs').then(m => console.log(typeof m.readHookContext))"` — should print `function`.
Run `node -e "import('./lib/index.mjs').then(m => console.log(typeof m.readHookContext))"` — should print `function`.
Grep `keyLiteralFlag` in `lib/tui-common.mjs` — should return zero matches.
Grep `fires events sequentially` in `lib/queue-processor.mjs` — should return one match.
  </verify>
  <done>
`lib/hook-context.mjs` exists with `readHookContext` export. `lib/index.mjs` re-exports it. `sendKeysToTmux` has 2 params (no keyLiteralFlag). `queue-processor.mjs` has inline mutation safety comment.
  </done>
</task>

<task type="auto">
  <name>Task 2: Refactor all 3 handlers — use readHookContext, add debug logging, add retryWithBackoff, fix promptFilePath</name>
  <files>events/stop/event_stop.mjs, events/session_start/event_session_start.mjs, events/user_prompt_submit/event_user_prompt_submit.mjs</files>
  <action>
This task applies Findings 3.1 (DRY), 3.2 (debug logging), 3.3 (promptFilePath), and 3.8 (retryWithBackoff) to all three handlers. Each handler gets the same structural changes:

**Common changes for all 3 handlers:**

1. **Replace boilerplate with `readHookContext`** — Remove the duplicated stdin/JSON/session/agent block. Replace with:
   ```javascript
   const hookContext = readHookContext('event_XXXX');
   if (!hookContext) process.exit(0);
   const { hookPayload, sessionName, resolvedAgent } = hookContext;
   ```

2. **Add debug logging on handler-specific guard failures** — Each handler has its own guards after the shared context. Each guard exit gets a `debug`-level `appendJsonlEntry`. Use pattern:
   ```javascript
   if (!condition) {
     appendJsonlEntry({ level: 'debug', source: 'event_XXXX', message: 'Reason — skipping', session: sessionName });
     process.exit(0);
   }
   ```

3. **Wrap `wakeAgentViaGateway` in `retryWithBackoff`** — Every call becomes:
   ```javascript
   await retryWithBackoff(
     () => wakeAgentViaGateway({ ... }),
     { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: 'wake-on-XXXX', sessionName }
   );
   ```
   The `retryWithBackoff` import comes from `../../lib/index.mjs` (already exported there).

4. **Remove imports no longer needed** — `readFileSync`, `execFileSync`, `resolveAgentFromSession` are now inside `readHookContext`. Remove from handler imports. Keep `resolve`, `dirname`, `fileURLToPath` only if still needed (stop handler needs them; session_start and user_prompt_submit will not after promptFilePath fix).

---

**event_stop.mjs specific changes:**

- Import `readHookContext` and `retryWithBackoff` from `../../lib/index.mjs`
- Remove `readFileSync` and `execFileSync` imports (now in hook-context.mjs)
- Keep `resolveAgentFromSession` REMOVED from imports — comes via readHookContext
- Keep `resolve`, `dirname`, `fileURLToPath` — still needed for promptFilePath (stop handler resolves relative to own directory, which is correct)
- The re-entrancy guard (`stop_hook_active`) stays AFTER readHookContext — it is stop-specific:
  ```javascript
  const hookContext = readHookContext('event_stop');
  if (!hookContext) process.exit(0);
  const { hookPayload, sessionName, resolvedAgent } = hookContext;

  if (hookPayload.stop_hook_active === true) {
    appendJsonlEntry({ level: 'debug', source: 'event_stop', message: 'Re-entrancy guard — stop_hook_active is true', session: sessionName });
    process.exit(0);
  }
  ```
- Add debug log for `!lastAssistantMessage` guard
- Add debug log for `awaits-mismatch` and `no-active-command` queue results
- Wrap BOTH `wakeAgentViaGateway` calls (queue-complete path and fresh-wake path) in `retryWithBackoff`
- promptFilePath stays as-is (already correct — resolves from own directory)

**event_session_start.mjs specific changes:**

- Import `readHookContext` and `retryWithBackoff` from `../../lib/index.mjs`
- Remove `readFileSync`, `execFileSync`, `resolveAgentFromSession` imports
- Remove `resolve`, `dirname`, `fileURLToPath` imports (no longer needed after promptFilePath fix)
- Import `SKILL_ROOT` from `../../lib/paths.mjs`
- Import `resolve` from `node:path` (still needed for SKILL_ROOT-based resolve)
- Fix promptFilePath (Finding 3.3): Replace:
  ```javascript
  const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'stop', 'prompt_stop.md');
  ```
  With:
  ```javascript
  const promptFilePath = resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md');
  ```
- Wrap BOTH `wakeAgentViaGateway` calls (queue-complete and stale-archive) in `retryWithBackoff`

**event_user_prompt_submit.mjs specific changes:**

- Import `readHookContext` and `retryWithBackoff` from `../../lib/index.mjs`
- Remove `readFileSync`, `execFileSync`, `resolveAgentFromSession` imports
- Remove `dirname`, `fileURLToPath` imports (no longer needed)
- Import `SKILL_ROOT` from `../../lib/paths.mjs`
- Import `resolve` from `node:path` (still needed for SKILL_ROOT-based resolve)
- Fix promptFilePath (Finding 3.3): Replace:
  ```javascript
  const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'stop', 'prompt_stop.md');
  ```
  With:
  ```javascript
  const promptFilePath = resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md');
  ```
- Note: UserPromptSubmit currently parses JSON just to validate but does not use hookPayload. With readHookContext, `hookPayload` is available from the context — keep it destructured but unused (add a comment explaining it is validated but unused per original design).
- Wrap the single `wakeAgentViaGateway` call in `retryWithBackoff`
  </action>
  <verify>
For each handler, run `node --check events/stop/event_stop.mjs`, `node --check events/session_start/event_session_start.mjs`, `node --check events/user_prompt_submit/event_user_prompt_submit.mjs` — all must pass syntax check.
Grep `readFileSync.*stdin` across all 3 handler files — should return zero matches (moved to hook-context.mjs).
Grep `readHookContext` across all 3 handler files — should return one match per file (3 total).
Grep `retryWithBackoff` across all 3 handler files — should return at least one match per file.
Grep `\.\./stop/` across session_start and user_prompt_submit — should return zero matches (replaced with SKILL_ROOT).
Grep `SKILL_ROOT` across session_start and user_prompt_submit — should return one match per file.
Grep `level.*debug` across all 3 handler files — should return at least one match per file (guard failure logging).
  </verify>
  <done>
All 3 handlers use `readHookContext` instead of duplicated boilerplate. Every guard failure logs a debug JSONL entry. All `wakeAgentViaGateway` calls wrapped in `retryWithBackoff`. `promptFilePath` in session_start and user_prompt_submit resolves via `SKILL_ROOT`. No handler imports `readFileSync` or `execFileSync` directly.
  </done>
</task>

<task type="auto">
  <name>Task 3: Add queue-overwrite warning in tui-driver.mjs</name>
  <files>bin/tui-driver.mjs</files>
  <action>
Add an `existsSync` check before `writeQueueFileAtomically` in `bin/tui-driver.mjs` (Finding 3.6).

Add `existsSync` to the import from `node:fs` (or import from a suitable source — check if it is available via lib). Actually, `tui-driver.mjs` does not import from `node:fs` currently. Add:
```javascript
import { existsSync } from 'node:fs';
```

Before the `writeQueueFileAtomically(queueFilePath, queueData)` call (around line 112), add:

```javascript
if (existsSync(queueFilePath)) {
  appendJsonlEntry({
    level: 'warn',
    source: 'tui-driver',
    message: 'Overwriting existing queue — previous queue may have been incomplete',
    session: sessionName,
  }, sessionName);
}
```

This is a warn-level log entry, not a blocking guard. The overwrite still happens — the warning makes the event visible in JSONL for diagnostics.
  </action>
  <verify>
Run `node --check bin/tui-driver.mjs` — must pass syntax check.
Grep `existsSync` in `bin/tui-driver.mjs` — should return one match.
Grep `Overwriting existing queue` in `bin/tui-driver.mjs` — should return one match.
  </verify>
  <done>
`tui-driver.mjs` logs a warn-level JSONL entry when an existing queue file would be overwritten. The overwrite still proceeds (by design) but the event is now visible in logs.
  </done>
</task>

</tasks>

<verification>
1. `node --check lib/hook-context.mjs` passes
2. `node --check lib/tui-common.mjs` passes
3. `node --check events/stop/event_stop.mjs` passes
4. `node --check events/session_start/event_session_start.mjs` passes
5. `node --check events/user_prompt_submit/event_user_prompt_submit.mjs` passes
6. `node --check bin/tui-driver.mjs` passes
7. Grep `readFileSync.*stdin` across events/ returns zero matches (boilerplate eliminated from handlers)
8. Grep `keyLiteralFlag` across lib/ returns zero matches
9. Grep `\.\./stop/` across events/ returns zero matches
10. Grep `retryWithBackoff` across events/ returns at least 3 matches
</verification>

<success_criteria>
All 6 code review findings from REVIEW.md Section 8 are resolved:
1. readHookContext extracts 15 lines of shared handler boilerplate into one place
2. Every guard-clause exit across all handlers logs a debug JSONL entry
3. All wakeAgentViaGateway calls wrapped in retryWithBackoff (3 attempts / 2s base)
4. sendKeysToTmux parameter list cleaned (keyLiteralFlag removed, hardcoded internally)
5. promptFilePath in session_start and user_prompt_submit uses SKILL_ROOT resolution
6. tui-driver.mjs warns on queue file overwrite
All files pass `node --check` syntax validation.
</success_criteria>

<output>
After completion, create `.planning/quick/9-fix-all-6-phase-03-code-review-findings-/9-SUMMARY.md`
</output>
