# Phase 03 Code Review: Stop Event Full-Stack (tui-common, queue-processor, tui-driver, event handlers)

**Reviewer:** Claude (gsd-executor)
**Date:** 2026-02-20
**Scope:** All 7 Phase 03 artifacts — `lib/tui-common.mjs`, `lib/queue-processor.mjs`, `bin/tui-driver.mjs`, `events/stop/event_stop.mjs`, `events/stop/prompt_stop.md`, `events/session_start/event_session_start.mjs`, `events/user_prompt_submit/event_user_prompt_submit.mjs`
**Phase 03 commits:** `9eba7de`, `7764769`, plus Plans 02 and 03 commits
**Post-phase fixes (quick task 7 — already applied):** `294a8c2`, `566b84a`, `8848b7a` — DRY violation fixed, JSON.parse guards added, absolute path in prompt_stop.md corrected. **These are NOT re-flagged below.**

---

## 1. Executive Summary

Phase 03 delivered a working end-to-end autonomous driving pipeline. Three plans produced seven files — two lib modules, one bin script, three event handlers, and a prompt file — that together implement the full cycle: agent wakes, calls tui-driver, queue is created, hooks fire, queue advances, agent wakes again on completion. The architecture decisions from the planning phase (handler = dumb plumbing, lib = brain, no delays between send-keys, discriminated action returns) were applied consistently.

The most impressive quality in Phase 03 is the coherence of the architecture. Every file has a clear single job, every boundary is respected, and the handler boilerplate is genuinely thin — roughly 50 lines per handler, most of which is guard clauses and a single lib function call. The discriminated action pattern in `processQueueForHook` is well-executed: callers can respond to each outcome without inspecting queue internals.

There are meaningful weaknesses. The three event handlers share approximately 15 lines of identical boilerplate (stdin read, JSON.parse guard, tmux session resolution, agent resolution) that is duplicated verbatim rather than extracted. The handlers exit 0 silently on every guard failure with no log entry, making it impossible to diagnose why a handler exited early in production. Two handlers resolve `promptFilePath` by navigating `../stop/` from their own directory — a cross-handler coupling that breaks if directory structure changes. `queue-processor.mjs` mutates parsed JSON objects in place before writing them back. These are all fixable issues worth addressing before Phase 04 adds more handlers.

Overall quality: **Good** — architecture sound, individual file quality high, cross-cutting concerns have room to improve.

---

## 2. What Was Done Well

### 2.1 Thin Handlers — Handler = Dumb Plumbing

The handler-as-plumbing principle is executed correctly. Each event handler reads stdin, resolves session and agent, delegates to lib, and exits. No business logic lives in the handler files. The most complex handler (`event_stop.mjs`) is 128 lines including imports, JSDoc, and comments — and its business logic is essentially two function calls (`processQueueForHook`, `wakeAgentViaGateway`) and a regex extraction block.

`event_session_start.mjs` is 110 lines with all queue logic delegated to lib:

```javascript
// events/session_start/event_session_start.mjs lines 52-72
if (source === 'clear') {
  const queueResult = processQueueForHook(sessionName, 'SessionStart', 'clear', null);

  if (queueResult.action === 'queue-complete') {
    wakeAgentViaGateway({ ... });
  }

  process.exit(0);
}
```

The handler does not know anything about queue file paths, how status transitions work, or how command IDs are assigned. It only knows: call `processQueueForHook`, check the action, wake agent if needed, exit. This is the right abstraction boundary.

### 2.2 Discriminated Action Returns in processQueueForHook

`processQueueForHook` returns a typed action object with no mixed semantics — each discriminant is a distinct string:

```javascript
// lib/queue-processor.mjs lines 99-115
if (!existsSync(queueFilePath)) {
  return { action: 'no-queue' };
}

// ...

if (!hookNameMatches || !subtypeMatches) {
  return { action: 'awaits-mismatch' };
}
```

```javascript
// lib/queue-processor.mjs lines 138-151
return { action: 'advanced', command: nextPendingCommand.command };

// ...

return { action: 'queue-complete', summary: buildQueueCompleteSummary(queueData) };
```

The five discriminants (`no-queue`, `no-active-command`, `awaits-mismatch`, `advanced`, `queue-complete`) cover all cases exhaustively. Callers can pattern-match on `queueResult.action` and know exactly what happened without inspecting queue internals. This is a good API design — the lib controls state, the handler reacts to outcomes.

### 2.3 Guard Clauses — No Nested Conditionals

All three handlers use guard clauses consistently, matching the Phase 02 pattern:

```javascript
// events/stop/event_stop.mjs lines 36-56 (representative of all three handlers)
if (hookPayload.stop_hook_active === true) {
  process.exit(0);
}

if (!sessionName) {
  process.exit(0);
}

if (!resolvedAgent) {
  process.exit(0);
}

if (!lastAssistantMessage) {
  process.exit(0);
}
```

Maximum nesting depth in any handler: 2 levels (if block inside function). The happy path proceeds at the top level of `main()` with no indentation layering.

### 2.4 Atomic Queue Writes (tmp + rename)

```javascript
// lib/queue-processor.mjs lines 49-54
export function writeQueueFileAtomically(queueFilePath, queueData) {
  mkdirSync(dirname(queueFilePath), { recursive: true });
  const temporaryFilePath = queueFilePath + '.tmp';
  writeFileSync(temporaryFilePath, JSON.stringify(queueData, null, 2), 'utf8');
  renameSync(temporaryFilePath, queueFilePath);
}
```

The tmp-then-rename pattern is correct POSIX-atomic for this context. On Linux, `renameSync` within the same filesystem is atomic — a reader either sees the old file or the new file, never a partial write. The `mkdirSync({ recursive: true })` ensures the `logs/queues/` directory always exists before the write. This is the same atomic write pattern established in Phase 02 for logger.mjs.

### 2.5 Tab Completion Logic for /gsd:* Commands

```javascript
// lib/tui-common.mjs lines 56-72
function typeGsdCommandWithTabCompletion(tmuxSessionName, commandText) {
  const spaceIndex = commandText.indexOf(' ');
  const hasArguments = spaceIndex !== -1;

  if (hasArguments) {
    const commandName = commandText.slice(0, spaceIndex);
    const commandArguments = commandText.slice(spaceIndex + 1);

    sendKeysToTmux(tmuxSessionName, commandName, '');
    sendSpecialKeyToTmux(tmuxSessionName, 'Tab');
    sendKeysToTmux(tmuxSessionName, ' ' + commandArguments, '');
  } else {
    sendKeysToTmux(tmuxSessionName, commandText, '');
    sendSpecialKeyToTmux(tmuxSessionName, 'Tab');
  }

  sendSpecialKeyToTmux(tmuxSessionName, 'Enter');
}
```

The logic correctly handles both `"/gsd:plan-phase 3"` (has arguments) and `"/gsd:resume-work"` (no arguments). For the arguments case, it types the command name, fires Tab for autocomplete to resolve the full command path, then types ` arguments` as a continuation. This is the correct Claude Code slash command interaction model.

### 2.6 Self-Explanatory Naming (CLAUDE.md Compliance)

Phase 03 maintains the naming standard established in earlier phases. All function and variable names read as plain English with no abbreviations:

- `typeCommandIntoTmuxSession`, `typeGsdCommandWithTabCompletion`, `typePlainCommandWithEnter`
- `sendKeysToTmux`, `sendSpecialKeyToTmux`
- `processQueueForHook`, `cancelQueueForSession`, `cleanupStaleQueueForSession`
- `resolveQueueFilePath`, `resolveStaleQueueFilePath`, `buildQueueCompleteSummary`
- `resolveAwaitsForCommand`, `parseCommandLineArguments`, `buildQueueData`
- Variables: `queueFilePath`, `activeCommand`, `nextPendingCommand`, `hookNameMatches`, `subtypeMatches`, `temporaryFilePath`, `completedCount`, `remainingCommands`

Zero abbreviations across all 7 files.

### 2.7 Queue Lifecycle Completeness

Phase 03 implements all four queue state transitions correctly:

| Transition | Function | Where called |
|------------|----------|--------------|
| Create queue + type first command | `writeQueueFileAtomically` + `typeCommandIntoTmuxSession` | `bin/tui-driver.mjs` |
| Advance queue + type next command | `processQueueForHook` → `typeCommandIntoTmuxSession` | `lib/queue-processor.mjs` |
| Cancel active queue (manual input) | `cancelQueueForSession` → `renameSync` to `.stale.json` | `event_user_prompt_submit.mjs` |
| Archive stale queue (session restart) | `cleanupStaleQueueForSession` → `renameSync` to `.stale.json` | `event_session_start.mjs` |

The lifecycle is closed — no queue state combination leads to an orphaned or unresolvable file.

### 2.8 Session Resolution via tmux display-message

```javascript
// events/stop/event_stop.mjs line 40
const sessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();
```

Resolving the session name from the live tmux context rather than from the hook payload UUID is the correct decision. Hook payloads include `session_id` as a UUID, not the human-readable tmux session name that `resolveAgentFromSession` and queue filenames use. Using `tmux display-message` gets the actual session name the hook is running inside. The `execFileSync` with argument array is consistent with the Phase 02 pattern — no shell interpolation.

### 2.9 Re-entrancy Guard in event_stop.mjs

```javascript
// events/stop/event_stop.mjs lines 36-38
if (hookPayload.stop_hook_active === true) {
  process.exit(0);
}
```

The `stop_hook_active` guard prevents the Stop handler from triggering itself when it wakes the agent via gateway (which would fire another Stop event). This is a non-obvious operational requirement that was correctly handled. Without this guard, the system would enter an infinite wake loop.

### 2.10 SRP: Internal Helpers Are Unexported

`tui-common.mjs` exports only `typeCommandIntoTmuxSession`. The internal helpers `typeGsdCommandWithTabCompletion`, `typePlainCommandWithEnter`, `sendKeysToTmux`, and `sendSpecialKeyToTmux` are unexported functions in the same module. This is correct SRP — callers do not need to know about the Tab completion split or the key-literal flag. The public API surface is one function.

Similarly, `queue-processor.mjs` keeps `resolveStaleQueueFilePath` and `buildQueueCompleteSummary` unexported. Internal helpers stay internal.

### 2.11 Proper Error Boundaries

All three handlers and `bin/tui-driver.mjs` have top-level error boundaries:

```javascript
// events/stop/event_stop.mjs lines 125-128
main().catch((caughtError) => {
  process.stderr.write(`[event_stop] Error: ${caughtError.message}\n`);
  process.exit(1);
});
```

Unhandled promise rejections surface to stderr with the handler name as a prefix. This is consistent across all handlers and `tui-driver.mjs`. The prefix (`[event_stop]`, `[event_session_start]`, `[event_user_prompt_submit]`) identifies the source when multiple hooks fire simultaneously and stderr entries interleave.

---

## 3. What Could Be Improved

### 3.1 Handlers Share ~15 Lines of Identical Boilerplate — DRY Violation

**Found across:** All three handlers

The stdin-to-agent resolution block is duplicated verbatim in all three event handlers:

```javascript
// Identical in event_stop.mjs (lines 28-50), event_session_start.mjs (lines 28-46),
// event_user_prompt_submit.mjs (lines 23-40)
const rawStdin = readFileSync('/dev/stdin', 'utf8').trim();
let hookPayload;
try {
  hookPayload = JSON.parse(rawStdin);
} catch {
  process.exit(0);
}

const sessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();

if (!sessionName) {
  process.exit(0);
}

const resolvedAgent = resolveAgentFromSession(sessionName);

if (!resolvedAgent) {
  process.exit(0);
}
```

Three files. Identical code. If the stdin read logic needs to change (e.g., async stdin, different trimming), it must be updated in three places. When Phase 04 adds two more handlers, this grows to five copies.

**Alternative:** Extract to `lib/hook-context.mjs` (or add to existing lib):

```javascript
// hypothetical lib/hook-context.mjs
export function readHookContext() {
  const rawStdin = readFileSync('/dev/stdin', 'utf8').trim();
  let hookPayload;
  try {
    hookPayload = JSON.parse(rawStdin);
  } catch {
    return null; // Caller checks for null and exits 0
  }

  const sessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();
  if (!sessionName) return null;

  const resolvedAgent = resolveAgentFromSession(sessionName);
  if (!resolvedAgent) return null;

  return { hookPayload, sessionName, resolvedAgent };
}
```

**Handler usage (event_stop.mjs) becomes:**

```javascript
const hookContext = readHookContext();
if (!hookContext) process.exit(0);
const { hookPayload, sessionName, resolvedAgent } = hookContext;
```

This reduces each handler's boilerplate from 15 lines to 3, and puts the shared logic in one place.

**Pros of extracted approach:** Single change point, less boilerplate, consistent behavior across all handlers.

**Cons of extracted approach:** The re-entrancy guard (`stop_hook_active`) is Stop-specific and cannot go into shared context. The handler still needs one bespoke guard after calling `readHookContext`. Minor additional module to document.

**Verdict:** Fix before Phase 04. The duplication will only grow with more handlers.

---

### 3.2 Silent exit(0) on Guard Failure — No Debug Logging

**Found across:** All three handlers

Every guard clause exits 0 silently with no log entry:

```javascript
// events/stop/event_stop.mjs lines 43-44
if (!sessionName) {
  process.exit(0);
}

// events/stop/event_stop.mjs lines 48-50
if (!resolvedAgent) {
  process.exit(0);
}

// events/stop/event_stop.mjs lines 54-56
if (!lastAssistantMessage) {
  process.exit(0);
}
```

In production, when a handler silently exits without doing anything, there is no way to diagnose why. A hook fires, nothing happens, no JSONL entry is written. The operator cannot distinguish between:
- "Handler ran, session is unmanaged, exited correctly"
- "Handler ran, could not resolve tmux session name"
- "Handler ran, JSON was malformed"
- "Handler ran, `last_assistant_message` was empty"

This makes production debugging extremely difficult.

**Alternative:** Log at `debug` or `info` level before each early exit:

```javascript
if (!sessionName) {
  appendJsonlEntry({ level: 'debug', source: 'event_stop', message: 'No tmux session name — skipping' });
  process.exit(0);
}

if (!resolvedAgent) {
  appendJsonlEntry({ level: 'debug', source: 'event_stop', message: 'Session not in agent registry — skipping', session: sessionName });
  process.exit(0);
}
```

**Pros of current approach:** Zero-noise for unmanaged sessions (which are the majority of hook firings). Logger is safe to call in hook context.

**Cons of current approach:** Every guard failure is invisible in production. Hard to diagnose misconfigurations (wrong session name in registry, disabled agent, etc.).

**Verdict:** Add debug-level log entries on guard failures. At minimum log the reason for every early exit. Use `debug` level to keep noise low in production. This is essential for operability.

---

### 3.3 promptFilePath Cross-Handler Coupling via ../stop/ Navigation

**Found in:** `event_session_start.mjs` (line 50), `event_user_prompt_submit.mjs` (line 59)

Both non-stop handlers navigate to the stop handler's directory to load `prompt_stop.md`:

```javascript
// events/session_start/event_session_start.mjs line 50
const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'stop', 'prompt_stop.md');

// events/user_prompt_submit/event_user_prompt_submit.mjs line 59
const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'stop', 'prompt_stop.md');
```

This is a cross-directory coupling. `event_session_start.mjs` has a hardcoded dependency on `events/stop/` existing and containing `prompt_stop.md`. If `prompt_stop.md` is ever renamed, moved, or if `session_start` needs its own prompt, both of these handlers need updating.

`event_stop.mjs` does it correctly:

```javascript
// events/stop/event_stop.mjs line 66
const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), 'prompt_stop.md');
```

**Alternative 1:** Use `SKILL_ROOT` to resolve from the skill root (more robust):

```javascript
import { SKILL_ROOT } from '../../lib/paths.mjs';
const promptFilePath = resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md');
```

This is explicit about crossing the directory boundary — the intent is clear. Moving the events directory would still require a change, but the path is at least semantically obvious.

**Alternative 2:** Extract the prompt path constant to `lib/paths.mjs`:

```javascript
// lib/paths.mjs
export const STOP_PROMPT_FILE_PATH = resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md');
```

**Pros of current approach:** Works correctly right now. The `../stop/` navigation is short.

**Cons of current approach:** If `session_start` or `user_prompt_submit` ever needs a different prompt, the coupling must be untangled under time pressure. Fragile if directory structure changes.

**Verdict:** Low priority for now (works correctly), but should be addressed before Phase 04 adds more handlers that may need different prompts. Use `SKILL_ROOT`-based resolution at minimum.

---

### 3.4 processQueueForHook Mutates Parsed JSON In Place

**Found in:** `lib/queue-processor.mjs` lines 117-119

```javascript
// lib/queue-processor.mjs lines 117-119
activeCommand.status = 'done';
activeCommand.result = lastAssistantMessage ?? null;
activeCommand.completed_at = new Date().toISOString();
```

`activeCommand` is a reference to an object inside `queueData.commands` (returned by `Array.find`). Mutating it mutates `queueData` directly — this is an in-place mutation of the parsed JSON object before it is written back.

This is not a bug in the current implementation — Node.js is single-threaded and the comment in the file header says "Claude Code fires events sequentially per session." The mutation happens, then `writeQueueFileAtomically` writes the mutated object to disk. The sequence is safe.

However, it is a subtle pattern. If the code is ever extended to handle concurrent writes (even accidentally), this mutation could produce inconsistent state. A reader expecting the original `queueData` after the mutation would see the modified version.

**Alternative:** Construct a new object instead of mutating:

```javascript
const updatedCommands = queueData.commands.map(command => {
  if (command.id !== activeCommand.id) return command;
  return {
    ...command,
    status: 'done',
    result: lastAssistantMessage ?? null,
    completed_at: new Date().toISOString(),
  };
});
const updatedQueueData = { ...queueData, commands: updatedCommands };
writeQueueFileAtomically(queueFilePath, updatedQueueData);
```

**Pros of current approach:** Simple, direct, correct for single-threaded sequential hooks. Less code.

**Cons of current approach:** Mutation makes the function non-pure and harder to test (the input object is modified as a side effect). Any caller that holds a reference to the original `queueData` will see the mutations.

**Verdict:** The current approach is safe given the sequential hook constraint. Add a comment explaining why in-place mutation is safe here, and keep it on the watch list if the system ever moves toward concurrent processing.

---

### 3.5 sendKeysToTmux Third Argument Pattern — Empty String as Literal Flag

**Found in:** `lib/tui-common.mjs` lines 95-98

```javascript
function sendKeysToTmux(tmuxSessionName, textToType, keyLiteralFlag) {
  execFileSync('tmux', ['send-keys', '-t', tmuxSessionName, textToType, keyLiteralFlag], {
    stdio: 'pipe',
  });
}
```

The function accepts a `keyLiteralFlag` parameter that callers pass as `''` (empty string) to instruct tmux to treat the preceding argument as literal text rather than a key name. The comment explains the intent:

```
// The empty string as the last argument prevents tmux from interpreting
// the text as a key name.
```

However, there are two concerns:

**Concern 1 — Portability:** This is an undocumented tmux behavior. The tmux manual does not officially document that an empty string as a trailing argument suppresses key-name interpretation. It is observed behavior that works in practice. If a future tmux version changes this behavior, `sendKeysToTmux` silently breaks.

**Concern 2 — API design:** The `keyLiteralFlag` parameter is always `''` at every call site. The caller should not need to know about this internal tmux mechanism:

```javascript
// tui-common.mjs lines 64, 68
sendKeysToTmux(tmuxSessionName, commandName, '');
sendKeysToTmux(tmuxSessionName, ' ' + commandArguments, '');
```

The empty string is an implementation detail of `sendKeysToTmux` — it should be hardcoded internally, not passed by the caller.

**Alternative:**

```javascript
function sendKeysToTmux(tmuxSessionName, textToType) {
  // The trailing empty string prevents tmux from interpreting textToType as a key name.
  // This is observed tmux behavior (not documented in manual) but consistent across tmux 3.x.
  execFileSync('tmux', ['send-keys', '-t', tmuxSessionName, textToType, ''], {
    stdio: 'pipe',
  });
}
```

Remove `keyLiteralFlag` from the signature; hardcode `''` inside the function.

**Verdict:** Fix the API design issue — remove `keyLiteralFlag` from the parameter signature and hardcode `''` inside `sendKeysToTmux`. Add a comment explaining the tmux behavior. The portability concern is low risk for the Linux/tmux-3.x target environment.

---

### 3.6 tui-driver.mjs Does Not Guard Against Overwriting an Existing Queue

**Found in:** `bin/tui-driver.mjs` lines 112-123

```javascript
const queueData = buildQueueData(commandTexts);
const queueFilePath = resolveQueueFilePath(sessionName);

writeQueueFileAtomically(queueFilePath, queueData);
```

If a queue file already exists for the session (a previous queue that did not complete), `tui-driver.mjs` silently overwrites it without warning or logging. The in-progress queue is lost with no diagnostic trace.

This could happen if:
- An agent calls `tui-driver.mjs` twice on the same session without waiting for the first queue to complete
- A hook delivery failure leaves a queue partially advanced
- A human manually triggers `tui-driver.mjs` while a session is mid-queue

**Alternative:** Check for existing queue before writing:

```javascript
if (existsSync(queueFilePath)) {
  process.stderr.write(`Warning: Overwriting existing queue for session "${sessionName}"\n`);
  appendJsonlEntry({
    level: 'warn',
    source: 'tui-driver',
    message: 'Overwriting existing queue — previous queue may have been incomplete',
    session: sessionName,
  }, sessionName);
}
```

Or add an `--overwrite` flag and fail loudly if a queue exists without it.

**Verdict:** At minimum, add a JSONL warning log entry when an existing queue is overwritten. Silent overwrite is operationally dangerous. A warn log costs nothing and makes the event visible.

---

### 3.7 event_stop.mjs Regex May Over-Match or Under-Match Suggested Commands

**Found in:** `events/stop/event_stop.mjs` line 88

```javascript
const commandMatches = lastAssistantMessage.match(/\/(?:gsd:[a-z-]+(?:\s+[^\s`]+)?|clear)/g) || [];
```

This regex attempts to extract GSD slash commands from the assistant's response. Several edge cases:

**Over-matching:**
- `/clear` inside a URL (`https://example.com/clear/cache`) would match.
- `/gsd:plan-phase` inside a code block (e.g., in a code example showing how to use the command) would match even though Claude Code is not recommending running it.
- `/clear` in a sentence like "You should /clear the queue first" would match.

**Under-matching:**
- The character class `[^\s\`]+` for arguments prevents multi-word arguments: `/gsd:execute-phase Phase 03` would match as `/gsd:execute-phase` (stops at the first space). This is correct for most GSD commands but depends on argument structure.
- Commands with hyphens only in names (not arguments): `[a-z-]+` is correct for GSD command names.

**Alternative for over-matching:** Check if the match appears at the start of a line or after a newline (Claude Code typically formats commands one-per-line):

```javascript
const commandMatches = lastAssistantMessage.match(/(?:^|\n)\s*\/(gsd:[a-z-]+(?:\s+[^\s`]+)?|clear)/gm) || [];
```

**Alternative for the extraction approach:** Consider whether the regex extraction adds meaningful value. The agent receiving the wake-up call can read `last_assistant_message` directly and make its own extraction decision. The `suggested_commands` block is a convenience, not the primary content.

**Verdict:** The regex over-matching (URLs, code blocks) is a real concern but low-frequency in practice. Add a note to the `prompt_stop.md` that suggested commands may include false positives, and the agent should verify before executing. Or add a line-anchor to reduce over-matching. The under-matching for multi-word arguments is acceptable given GSD command structure.

---

### 3.8 wakeAgentViaGateway Called Without retryWithBackoff in Handlers

**Found in:** `events/stop/event_stop.mjs` lines 68-78, 102-112; `events/session_start/event_session_start.mjs` lines 58-68; `events/user_prompt_submit/event_user_prompt_submit.mjs` lines 61-71

All three handlers call `wakeAgentViaGateway` directly without wrapping in `retryWithBackoff`:

```javascript
// events/stop/event_stop.mjs lines 68-78
wakeAgentViaGateway({
  openclawSessionId: resolvedAgent.openclaw_session_id,
  messageContent,
  promptFilePath,
  eventMetadata: { ... },
  sessionName,
});
```

Phase 02 review (Section 5.4) identified this as Risk 3: "Phase 3 must document and deliberately override these defaults." Phase 03 resolved this by not using retry at all — a different tradeoff.

**Consequence:** If the OpenClaw gateway is temporarily unavailable (restart, network hiccup), the agent wake-up attempt silently fails. The JSONL log from `gateway.mjs` will record the error, but the agent is never notified of the Stop event. The coding session continues and subsequent events may fire, but the agent is not aware of what Claude Code just completed.

**Alternative:** Wrap in `retryWithBackoff` with conservative settings:

```javascript
import { retryWithBackoff } from '../../lib/index.mjs';

await retryWithBackoff(
  () => wakeAgentViaGateway({ ... }),
  { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: 'wake-on-stop', sessionName },
);
```

**Pros of no-retry approach:** Simpler handlers. Gateway failures are rare. Hook process exits faster.

**Cons of no-retry approach:** A single transient gateway failure causes the agent to miss an event with no recovery. In a long multi-command queue, a missed wake-up on queue-complete leaves the agent unaware the queue finished.

**Verdict:** Add `retryWithBackoff` with 3 attempts / 2s base for all `wakeAgentViaGateway` calls in handlers. The Phase 02 review explicitly anticipated this and `retryWithBackoff` was built for exactly this purpose. Not using it wastes the investment.

---

## 4. Phase 01 and Phase 02 Review Alignment

| Phase 01/02 Finding | Phase 03 Outcome | Notes |
|---------------------|-----------------|-------|
| REV-3.3: `execSync` → `execFileSync` with arg arrays | Applied | All tmux calls in tui-common.mjs use `execFileSync` with explicit arrays (lines 96-98, 108-110) |
| REV-3.5: `sleepSeconds` via shell → Promise sleep | Not needed | Phase 03 deliberately has no delays; `execFileSync` blocking provides pacing (design decision logged in STATE.md) |
| REV-2.7 (P02): Single timestamp capture | Applied | `processQueueForHook` and `cancelQueueForSession` call `new Date().toISOString()` once per operation |
| REV-2.3 (P02): `SKILL_ROOT` duplication → `lib/paths.mjs` | Applied | `lib/paths.mjs` exists; `queue-processor.mjs` imports from it correctly (line 17) |
| REV-5.4 (P02): `promptFilePath` must be absolute | Partially applied | `event_stop.mjs` uses `import.meta.url` correctly; `event_session_start.mjs` and `event_user_prompt_submit.mjs` use `../stop/` navigation (Section 3.3 above) |
| REV-5.4 (P02): Retry defaults in hook context | Not applied | No `retryWithBackoff` used in any handler (Section 3.8 above) |
| REV-2.4 (P02): Guard clause pattern | Applied | All three handlers use consistent guard-clause-first pattern matching Phase 02 style |
| REV-2.1 (P02): Single source for shared logging | Applied | `appendJsonlEntry` imported from lib — not reimplemented in Phase 03 files |
| REV-2.2 (P02): SRP — one responsibility per file | Applied | Each Phase 03 file has one clear responsibility; no mixed concerns |
| REV-2.5 (P02): Three-tier error philosophy | Partially applied | `tui-common.mjs` throws on missing args (correct); handlers silent-exit on guard failures — no logging (Section 3.2) |
| QT7 fixes (already applied): DRY writeQueueFileAtomically | Applied | Promoted to lib export; `tui-driver.mjs` imports from lib |
| QT7 fixes: JSON.parse guards | Applied | All three handlers guard JSON.parse with try/catch |
| QT7 fixes: Absolute path in prompt_stop.md | Applied | Uses full absolute path to tui-driver.mjs |

**Summary:** 8 of 12 prior findings were applied correctly. 3 were not applied (`promptFilePath` coupling, no retry wrapping, no guard-failure logging). 1 was deliberately bypassed by design (no delays needed).

---

## 5. Progress Toward Autonomous Driving Goal

**Goal:** "When Claude Code fires any hook event, the right agent wakes up with the right context and knows exactly which GSD slash command to type next."

### 5.1 Pieces Now in Place

| Piece | Module | Completeness |
|-------|--------|--------------|
| tmux send-keys with Tab completion | `lib/tui-common.mjs` | Complete |
| Command queue create + advance + cancel + archive | `lib/queue-processor.mjs` | Complete |
| Queue creation entry point (CLI) | `bin/tui-driver.mjs` | Complete |
| Stop event handler | `events/stop/event_stop.mjs` | Complete — wakes agent and advances queue |
| SessionStart handler (clear + startup) | `events/session_start/event_session_start.mjs` | Complete |
| UserPromptSubmit handler (queue cancel) | `events/user_prompt_submit/event_user_prompt_submit.mjs` | Complete |
| Agent prompt with GSD command guidance | `events/stop/prompt_stop.md` | Complete — covers stop, queue-complete, and do-nothing cases |
| Re-entrancy guard (stop_hook_active) | `event_stop.mjs` line 36 | Complete |
| Stale queue cleanup on session restart | `event_session_start.mjs` + `cleanupStaleQueueForSession` | Complete |

For the Stop event: the full cycle works. An agent can call `tui-driver.mjs` with a command array, Claude Code runs the commands, each Stop event advances the queue, and the agent is woken with a completion summary when all commands are done. Manual input correctly cancels the queue and notifies the agent.

### 5.2 What Is Still Missing for Phase 04

**Pre-tool-use and Post-tool-use handlers:** Phase 04 targets AskUserQuestion control. These hooks fire before and after tool calls, enabling the system to intercept question prompts and automatically answer them via the agent. These handlers are not implemented.

**Per-event prompts for new handlers:** Phase 04 will need its own prompt files for PreToolUse/PostToolUse events. The current `prompt_stop.md` covers Stop, queue-complete, and stale-archive scenarios. New event types need new prompt guidance.

**`retryWithBackoff` integration:** As noted in Section 3.8, gateway calls are currently one-shot. Before Phase 04 adds more handlers, retry wrapping should be added to the existing three handlers to establish the pattern.

**`readHookContext` shared helper:** Phase 04 will add two more handlers. Extracting the shared boilerplate now (Section 3.1) avoids a five-file duplication problem.

**Hook registration (settings.json):** This is infrastructure that may be in place already (if existing hooks are live) but was not part of Phase 03 review scope.

### 5.3 Risk Assessment for Phase 04

**Risk 1 — Boilerplate multiplication:** If Phase 04 adds two handlers without extracting `readHookContext`, the 15-line block is duplicated five times. Recommend extracting before Phase 04 starts.

**Risk 2 — Prompt file proliferation:** Phase 04 handlers may reuse `prompt_stop.md` or need their own prompts. The Phase 03 decision to reuse the Stop prompt for SessionStart and UserPromptSubmit works because those events are queue-advance triggers. PreToolUse/PostToolUse (AskUserQuestion) likely need different guidance about when to auto-answer vs escalate. Plan the prompt strategy before Phase 04 implementation.

**Risk 3 — Queue interaction for new event types:** PreToolUse/PostToolUse events may not fit the current queue model (which is built around Stop and SessionStart). The queue was designed for sequential GSD slash commands. AskUserQuestion interception is a different pattern. Evaluate whether the existing queue mechanism is the right tool or if a lighter-weight one-shot response pattern is needed.

**Risk 4 — Guard failure silence:** With no logging on guard exits, Phase 04 debugging will be difficult if handlers don't fire as expected. Resolve Section 3.2 before Phase 04 to make the system observable.

---

## 6. Scores

### Code Quality: 4/5

Clean architecture, correct abstractions, consistent style. The lib modules are well-implemented. Handler files are appropriately thin. Deductions for: `sendKeysToTmux` API exposes internal tmux mechanism through `keyLiteralFlag` parameter, `tui-driver.mjs` silently overwrites existing queues, `processQueueForHook` in-place mutation without explanation comment.

### DRY/SRP: 3/5

SRP is applied correctly throughout — every file and function has one responsibility. DRY has a meaningful violation: the 15-line handler boilerplate is duplicated three times (Section 3.1). This will become a five-file duplication in Phase 04 if not addressed. SRP score would be 5/5 on its own; the DRY deduction brings the combined score to 3.

### Naming Conventions: 5/5

Full CLAUDE.md compliance maintained. Zero abbreviations. Every name reads as a plain English phrase: `typeGsdCommandWithTabCompletion`, `resolveAwaitsForCommand`, `buildQueueCompleteSummary`, `cleanupStaleQueueForSession`. This is the naming standard the project maintains.

### Error Handling: 3/5

The three-tier philosophy from Phase 02 (`tui-common.mjs` throws, lib returns null/objects, handlers exit 0) is structurally correct. Deductions for: all guard failures in handlers are silent with no log entry (Section 3.2) — this is the most serious operability gap; `wakeAgentViaGateway` called without retry wrapping in all three handlers (Section 3.8); `tui-driver.mjs` silently overwrites existing queues without warning (Section 3.6). Phase 03 built the retry infrastructure in Phase 02 and chose not to use it.

### Security: 4/5

All tmux calls use `execFileSync` with argument arrays — no shell injection. No user-controlled strings passed to shell. Queue filenames are derived from session names (which are resolved from the live tmux context, not from user input). The regex in `event_stop.mjs` could over-match URLs or code blocks but does not introduce a security vulnerability — it affects suggestion quality, not security. Deduction for: `tui-driver.mjs` overwrite without guard (operational risk, not strictly security).

### Future-Proofing: 3/5

The queue-based architecture is sound and extensible for new event types. Deductions for: 15-line boilerplate duplication that grows with each new handler (Section 3.1); `promptFilePath` cross-directory coupling that will need untangling if prompts diverge per event (Section 3.3); no retry wrapping establishes a pattern of single-shot delivery that Phase 04 may copy; queue mutation without comment leaves a maintenance trap if concurrency is ever introduced (Section 3.4).

---

## 7. Summary Table

| File | Key Strength | Key Concern | Recommendation |
|------|-------------|-------------|----------------|
| `lib/tui-common.mjs` | Clean Tab completion logic; execFileSync arg arrays; SRP (one exported function) | `sendKeysToTmux` exposes internal `keyLiteralFlag` to callers; portability of empty-string tmux behavior | Remove `keyLiteralFlag` from parameter; hardcode `''` internally; add comment on tmux behavior |
| `lib/queue-processor.mjs` | Discriminated action returns; atomic writes; full lifecycle coverage; all internal helpers unexported | In-place JSON mutation before write (no comment explaining safety); no warning when overwriting | Add inline comment explaining why mutation is safe; add warn log in `writeQueueFileAtomically` if file exists |
| `bin/tui-driver.mjs` | Full validation pipeline; correct `resolveAwaitsForCommand` dispatch; proper error boundary | Silently overwrites existing queue — no log entry, no guard | Check for existing queue; add JSONL warn log entry when overwriting |
| `events/stop/event_stop.mjs` | Correct re-entrancy guard; command extraction; thin handler; proper promptFilePath resolution | Silent exit on every guard failure; no retry wrapping for gateway call | Add debug-level JSONL entries on guard exits; wrap `wakeAgentViaGateway` in `retryWithBackoff` |
| `events/stop/prompt_stop.md` | Clear do-nothing guidance; command types section; covers queue-complete case | Regex over-matching may include URLs/code examples in suggested commands | Add note that suggested commands may include false positives; agent should verify |
| `events/session_start/event_session_start.mjs` | Correct clear vs startup dispatch; stale queue archive + notification | Silent guard failures; `promptFilePath` navigates `../stop/` (cross-directory coupling); no retry | Log guard exits; use SKILL_ROOT to resolve prompt path; add retry |
| `events/user_prompt_submit/event_user_prompt_submit.mjs` | Clean queue cancel + agent notification; well-structured cancellation summary | Silent guard failures; `promptFilePath` navigates `../stop/`; no retry | Same as session_start — log exits, fix prompt path, add retry |

---

## 8. Refactoring Priorities for Phase 03.1

Based on this review, the following are recommended for a Phase 03.1 refactor (in priority order):

### Priority 1: Extract readHookContext shared helper (DRY — Section 3.1)
Eliminates 15-line duplication across 3 handlers (growing to 5 with Phase 04). Extract to `lib/hook-context.mjs` or add to existing lib. Commit as `refactor`.

### Priority 2: Add guard-failure debug logging (Operability — Section 3.2)
All guard exits in all three handlers should log a `debug`-level JSONL entry with the exit reason. Without this, production debugging is guesswork. Commit as `fix`.

### Priority 3: Add retryWithBackoff to gateway calls (Reliability — Section 3.8)
Wrap all `wakeAgentViaGateway` calls with `retryWithBackoff({ maxAttempts: 3, initialDelayMilliseconds: 2000 })`. The retry infrastructure was built in Phase 02 specifically for this use case. Commit as `fix`.

### Priority 4: Fix sendKeysToTmux API (API cleanliness — Section 3.5)
Remove `keyLiteralFlag` parameter from `sendKeysToTmux`; hardcode `''` internally. Add comment explaining the tmux behavior. Commit as `refactor`.

### Priority 5: Fix promptFilePath cross-directory coupling (Fragility — Section 3.3)
Replace `../stop/` navigation with `SKILL_ROOT`-based resolution in session_start and user_prompt_submit handlers. Commit as `refactor`.

### Priority 6: Add queue-overwrite warning in tui-driver.mjs (Operability — Section 3.6)
Check for existing queue file; log a JSONL warn entry if overwriting. Commit as `fix`.

---

*Review completed: 2026-02-20*
*Phase 03 verification score: All 3 plans — 12/12, 8/8, 10/10 must-haves verified*
*Quick task 7 fixes already applied: DRY (writeQueueFileAtomically), JSON.parse guards, absolute path in prompt_stop.md*
*Files reviewed: lib/tui-common.mjs, lib/queue-processor.mjs, bin/tui-driver.mjs, events/stop/event_stop.mjs, events/stop/prompt_stop.md, events/session_start/event_session_start.mjs, events/user_prompt_submit/event_user_prompt_submit.mjs*
