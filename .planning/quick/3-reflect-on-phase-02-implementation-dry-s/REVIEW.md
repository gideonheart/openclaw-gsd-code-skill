# Phase 02 Implementation Review: Shared Library

**Reviewer:** Claude (gsd-executor)
**Date:** 2026-02-20
**Scope:** All 6 lib files — `logger.mjs`, `json-extractor.mjs`, `retry.mjs`, `agent-resolver.mjs`, `gateway.mjs`, `index.mjs` — plus Phase 02 summaries, verification, UAT, and context.
**Phase commits:** `9e01e54` through `aa468f6`

---

## 1. Executive Summary

Phase 02 delivered a clean, well-structured shared library with zero external dependencies and consistent idiomatic ESM throughout. All six lib modules follow the same internal discipline: guard clauses at the top, a single responsibility per function, `node:` prefix imports, and logging that never throws. The 13/13 verification score and 6/6 UAT pass rate are not flattery — the code substantiates them.

What stands out most is how consistently Phase 02 applied the lessons from Phase 01.1. Every Phase 1 code review finding that was relevant to a Node.js library context shows up corrected: `execFileSync` with argument arrays in `gateway.mjs`, a single timestamp capture per log entry in `logger.mjs`, `O_APPEND` instead of `flock`, self-explanatory naming throughout. The shared library is the kind of foundation that does not need to be revisited before Phase 3 begins.

The honest tradeoffs are: `extractJsonField` only handles top-level fields (a limitation that will surface in Phase 3 when hooks send nested payloads like `payload.tool_name`); the logger swallows all errors without any last-resort stderr output; `SKILL_ROOT` is computed independently in both `logger.mjs` and `agent-resolver.mjs` rather than being shared; and the retry delay sequence (up to 42 minutes total) is aggressive enough to keep the calling hook process alive long past any reasonable gateway recovery window. These are not blocking issues for Phase 03, but they are worth tracking.

---

## 2. What Was Done Well

### 2.1 DRY Compliance — Single Source for Shared Logging

The most significant DRY choice in Phase 02 is that `appendJsonlEntry` is defined once in `logger.mjs` and imported by every other module that needs to log. This is the correct inversion of the Phase 1 bash pattern where each script reimplemented its own timestamp-and-append logic.

```javascript
// lib/json-extractor.mjs line 9
import { appendJsonlEntry } from './logger.mjs';

// lib/retry.mjs line 12
import { appendJsonlEntry } from './logger.mjs';

// lib/gateway.mjs line 16
import { appendJsonlEntry } from './logger.mjs';

// lib/agent-resolver.mjs line 12
import { appendJsonlEntry } from './logger.mjs';
```

Four importers, one definition. Any change to the logging format or atomic write mechanism propagates automatically. This is DRY working as intended.

### 2.2 SRP — Each Module Does Exactly One Thing

Each file has a single, named export that does one thing:

| File | Single Responsibility |
|------|-----------------------|
| `logger.mjs` | Append a JSONL record to a file |
| `json-extractor.mjs` | Extract a named field from a JSON string |
| `retry.mjs` | Retry an async function with exponential backoff |
| `agent-resolver.mjs` | Map a tmux session name to an agent config |
| `gateway.mjs` | Wake an agent via the OpenClaw CLI |
| `index.mjs` | Re-export all five functions from one entry point |

None of these modules does two things. `gateway.mjs` is the most complex (103 lines) but the complexity is justified: it handles parameter validation, prompt file reading, message assembly, CLI invocation, and dual-path logging (success and failure). Each of those steps is a necessary part of one responsibility: "wake the agent."

### 2.3 Naming Conventions (CLAUDE.md Compliance)

CLAUDE.md mandates self-explanatory names with no abbreviations. Phase 02 complies throughout.

Function names:
- `appendJsonlEntry` — not `append`, not `log`, not `writeLog`
- `extractJsonField` — not `getField`, not `extract`, not `parseField`
- `retryWithBackoff` — not `retry`, not `withRetry`, not `backoff`
- `resolveAgentFromSession` — not `getAgent`, not `findAgent`, not `lookupSession`
- `wakeAgentViaGateway` — not `wake`, not `deliver`, not `sendMessage`

Variable names inside functions follow the same rule:
- `registryFileContents`, `matchingAgent`, `entryTimestamp`, `combinedMessage`, `openclawArguments`, `fileDescriptor`, `logFilePrefix`, `delayMilliseconds`, `attemptNumber`

Not a single abbreviation across 356 lines of lib code.

### 2.4 Guard Clause Pattern — No Nested Conditionals

Every module uses guard clauses (early returns) instead of nested if blocks. The pattern is consistent: validate inputs at the top, return null or throw early, happy path proceeds without indentation.

`agent-resolver.mjs` is the clearest example — six guard clauses in sequence before the return:

```javascript
// lib/agent-resolver.mjs lines 25-66
export function resolveAgentFromSession(tmuxSessionName) {
  if (!tmuxSessionName) {
    return null;
  }

  if (!existsSync(AGENT_REGISTRY_PATH)) {
    return null;
  }

  let registry;
  try {
    const registryFileContents = readFileSync(AGENT_REGISTRY_PATH, 'utf8');
    registry = JSON.parse(registryFileContents);
  } catch (parseError) {
    appendJsonlEntry({ level: 'warn', ... });
    return null;
  }

  if (!Array.isArray(registry.agents)) {
    appendJsonlEntry({ level: 'warn', ... });
    return null;
  }

  const matchingAgent = registry.agents.find(...);

  if (!matchingAgent) {
    return null;
  }

  if (matchingAgent.enabled === false) {
    return null;
  }

  return matchingAgent;
}
```

Maximum nesting depth throughout the entire lib: 2 levels (try/catch inside a for loop in `retry.mjs`). This is exemplary guard clause discipline.

### 2.5 Error Handling Philosophy — Differentiated by Module

Phase 02 established three distinct error-handling contracts across the lib, each appropriate to its module's role:

**Logger (`logger.mjs`) — Never throws, swallows all errors:**
```javascript
// lib/logger.mjs lines 47-49
  } catch {
    // Silently swallow all errors — the logger must never crash the caller.
  }
```
Logging must not crash the calling hook. This matches the Phase 1 `|| true` pattern in bash.

**Resolver (`agent-resolver.mjs`) — Returns null silently for expected failures, logs unexpected ones:**
Silent null for missing session, missing registry file, disabled agent. JSONL warning for registry parse errors and malformed structure — these are unexpected and warrant visibility.

**Gateway (`gateway.mjs`) — Throws for required parameter failures, logs then re-throws on CLI failure:**
```javascript
// lib/gateway.mjs lines 45-55
  if (!openclawSessionId) {
    throw new Error('wakeAgentViaGateway: openclawSessionId is required');
  }
  ...
  } catch (caughtError) {
    appendJsonlEntry({ level: 'error', ... }, sessionName);
    throw caughtError;
  }
```
Gateway failures must surface to the caller so `retryWithBackoff` can react. Logging before re-throwing gives a JSONL trace even when retries are not configured.

This three-tier philosophy (swallow / return-null / throw) is coherent and will serve event handlers well in Phase 3.

### 2.6 ESM Patterns — Correct 2025 Node.js Idioms

All six files use the correct modern ESM conventions:

- `node:` prefix on every built-in import: `node:fs`, `node:path`, `node:url`, `node:child_process`
- `import.meta.url` + `dirname(fileURLToPath())` for SKILL_ROOT resolution
- `export function` (named export) rather than default exports — forces explicit import names at call sites
- Barrel re-export in `index.mjs` with no logic or side effects — 14 lines, pure re-exports

```javascript
// lib/index.mjs — the entire file
export { appendJsonlEntry } from './logger.mjs';
export { extractJsonField } from './json-extractor.mjs';
export { retryWithBackoff } from './retry.mjs';
export { resolveAgentFromSession } from './agent-resolver.mjs';
export { wakeAgentViaGateway } from './gateway.mjs';
```

### 2.7 Phase 1 Review Lessons Applied

Three specific Phase 01.1 fixes show up correctly applied in Phase 02:

**O_APPEND instead of flock:** Phase 1 used `flock -x` in bash. Phase 02's `logger.mjs` uses `O_APPEND | O_CREAT | O_WRONLY` flags, which provides equivalent atomic-append guarantees in Node.js without a lock file:
```javascript
// lib/logger.mjs lines 41-44
const fileDescriptor = openSync(
  logFilePath,
  constants.O_APPEND | constants.O_CREAT | constants.O_WRONLY,
);
```

**Single timestamp capture:** Phase 1 called `date -u` six times in one log block (REV-3.1). Phase 02 captures timestamp once:
```javascript
// lib/logger.mjs line 33
const entryTimestamp = new Date().toISOString();
```

**`execFileSync` with argument arrays:** Phase 1 used `execSync` with template string interpolation (REV-3.3). Phase 02's gateway uses `execFileSync` with an explicit argument array:
```javascript
// lib/gateway.mjs lines 72-76
const openclawArguments = [
  'agent',
  '--session-id', openclawSessionId,
  '--message', combinedMessage,
];
execFileSync('openclaw', openclawArguments, { stdio: 'pipe', timeout: GATEWAY_TIMEOUT_MILLISECONDS });
```

---

## 3. What Could Be Done Differently

### 3.1 `extractJsonField` Only Handles Top-Level Fields

**Current implementation:**
```javascript
// lib/json-extractor.mjs lines 43-51
if (!Object.hasOwn(parsedObject, fieldName)) {
  appendJsonlEntry({ level: 'warn', source: 'extractJsonField', message: 'Field not found in JSON', field: fieldName });
  return null;
}
return parsedObject[fieldName];
```

`fieldName` is a single key. There is no path-based access — `extractJsonField(json, 'payload.tool_name')` would look for a literal key named `'payload.tool_name'`, not a nested field.

**Alternative:** Accept dot-notation paths and resolve them:
```javascript
// hypothetical: extractJsonField(json, 'payload.tool_name')
const fieldValue = fieldPath.split('.').reduce((obj, key) => obj?.[key], parsedObject);
```

**Pros of current approach:** Simpler, no ambiguity about what `fieldName` means, easy to test, fast.

**Cons of current approach:** Phase 3 (Stop event) and Phase 4 (AskUserQuestion) hook payloads contain nested fields. The Stop hook payload includes `stop_hook_active` at the top level, but the PostToolUse hook includes `tool_use.input`, `tool_use.name` — nested. Callers will need two calls or manual chaining: `extractJsonField(extractJsonField(json, 'tool_use'), 'name')` — but that only works if the value is also JSON-serialized, which it may not be.

**Verdict:** Consider changing before Phase 4 (PostToolUse). Phase 3 (Stop) only needs `stop_hook_active` which is top-level, so it will not hit this limitation immediately. Add dot-notation path support as a non-breaking extension — `extractJsonField(json, 'tool_use.name')` — when Phase 4 planning begins.

### 3.2 Logger Silent Swallow Is Too Aggressive

**Current implementation:**
```javascript
// lib/logger.mjs lines 47-49
  } catch {
    // Silently swallow all errors — the logger must never crash the caller.
  }
```

This catches and discards all errors: disk full, missing log directory (despite `mkdirSync`), permission denied, invalid file descriptor.

**Alternative:** Swallow expected I/O errors but emit to stderr for unexpected ones:
```javascript
} catch (loggingError) {
  // Only swallow I/O errors. For unexpected error types, emit to stderr
  // so the issue surfaces without crashing the caller.
  if (loggingError.code === undefined || loggingError.code === 'ENOENT' || loggingError.code === 'ENOSPC') {
    return; // Expected I/O failures — silent
  }
  process.stderr.write(`[gsd-code-skill logger] Unexpected error: ${loggingError.message}\n`);
}
```

**Pros of current approach:** Absolute safety — nothing the logger does can ever surface to the caller. Hook scripts must be transparent.

**Cons of current approach:** A disk-full condition (`ENOSPC`) would silently stop all JSONL logging with no indication. An operator debugging why events are not appearing in logs would have no signal. Development errors (e.g., wrong log entry type passed to `JSON.stringify`) would also be silently discarded.

**Verdict:** Keep the swallow pattern for production safety, but consider adding a stderr fallback for errors that are not expected I/O failures. This is a low-priority improvement — the hook transparency requirement is real and outweighs the debuggability concern in most scenarios.

### 3.3 SKILL_ROOT Computed Twice

**Current situation:**
- `lib/logger.mjs` line 17: `const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));`
- `lib/agent-resolver.mjs` line 14: `const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));`

These are two separate computations of the same value. Both correctly resolve to the skill root, but the duplication means the `dirname(dirname(fileURLToPath(...)))` pattern must be replicated in every new lib module that needs to reference a file path.

**Alternative 1:** Dedicate a `lib/paths.mjs` module that exports `SKILL_ROOT`:
```javascript
// lib/paths.mjs
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
export const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
```

Then import where needed: `import { SKILL_ROOT } from './paths.mjs';`

**Alternative 2:** Accept the duplication as intentional — each module is self-contained, follows the Phase 01.1 established ESM bootstrap pattern, and computing `SKILL_ROOT` is a three-line O(1) operation.

**Pros of current approach:** Each module is independently self-contained. The pattern is established (both Phase 01.1 decisions log it). No additional module to document.

**Cons of current approach:** When Phase 3+ adds `events/stop/handler.mjs` at a different directory depth, the `dirname` call count changes (`dirname(dirname(dirname(...)))`) — the pattern breaks silently if the depth is wrong. A `lib/paths.mjs` would fix the depth once.

**Verdict:** Acceptable for Phase 02. Add `lib/paths.mjs` when the first event handler module needs `SKILL_ROOT` and demonstrates the depth ambiguity problem. Do not over-engineer prematurely.

### 3.4 Combined Message Format in `gateway.mjs` Is a Rigid Markdown Template

**Current implementation:**
```javascript
// lib/gateway.mjs lines 59-70
const combinedMessage = [
  '## Event Metadata',
  `- Event: ${eventMetadata.eventType}`,
  `- Session: ${eventMetadata.sessionName}`,
  `- Timestamp: ${eventMetadata.timestamp}`,
  '',
  '## Last Assistant Message',
  messageContent,
  '',
  '## Instructions',
  promptContent,
].join('\n');
```

The format is hardcoded markdown with fixed section order and headings. Every event handler that calls `wakeAgentViaGateway` gets the same structure regardless of the event type.

**Alternative:** Accept a message builder function or a structured template config:
```javascript
// hypothetical structured approach
export function wakeAgentViaGateway({ openclawSessionId, buildMessage, ... }) {
  const combinedMessage = buildMessage({ eventMetadata, messageContent, promptContent });
  ...
}
```

**Pros of current approach:** Consistent — every agent wake call looks identical from the receiving agent's perspective. Simpler function signature. No framework overhead. The format (metadata first, content second, instructions last) matches how humans read documents and was a deliberate decision.

**Cons of current approach:** If a future event type needs a different message structure (e.g., tool approval events that should foreground the tool name, or notification events that have no `last_assistant_message`), the hardcoded template cannot accommodate it without modifying `gateway.mjs` itself. The `messageContent` parameter is required to be a string but could be empty or irrelevant for some event types.

**Verdict:** Keep the current format. The markdown template covers all planned event types (Stop, AskUserQuestion, Notification, PostToolUse). If a genuinely different structure is needed, extend the `wakeParameters` object with an optional `customMessageBuilder` — do not refactor prematurely.

### 3.5 Retry Delay Sequence Is Aggressive for a Hook Process

**Current defaults:**
```javascript
// lib/retry.mjs line 47
const delayMilliseconds = initialDelayMilliseconds * Math.pow(2, attemptNumber - 1);
// Default: 5000ms base, 10 attempts
// Sequence: 5s, 10s, 20s, 40s, 80s, 160s, 320s, 640s, 1280s, 2560s
// Total potential wait: ~42 minutes
```

**Alternative defaults:** 3 attempts, 2s base — total potential wait ~6 seconds. Or a linear backoff with a cap.

**Pros of current approach:** Genuinely resilient to long gateway outages. The 10/10 attempt with a log message per retry gives full visibility. Caller controls the parameters.

**Cons of current approach:** A Claude Code hook that calls `retryWithBackoff(() => wakeAgentViaGateway(...))` with default parameters will hold the hook process alive for up to 42 minutes on persistent gateway failure. Claude Code may have its own hook timeout (the gateway has a 120s timeout per call, and retries multiply that). In practice, 10 attempts at defaults would take much longer than any reasonable hook timeout allows.

More importantly: the hook is blocking a Claude Code session while retrying. If the gateway is down, the user's coding session is not paused — Claude Code continues to fire more hook events. A stuck hook that retries for 42 minutes is worse than a fast-fail that lets the session continue.

**Verdict:** Consider changing the default `maxAttempts` to 3 and `initialDelayMilliseconds` to 2000 (total wait: ~6s). The 10-attempt/5s default may have been designed for a long-running background service, not a per-hook-event invocation. Document the tradeoff in the function's JSDoc.

### 3.6 Agent Registry Read on Every Call — No Caching

**Current implementation:**
```javascript
// lib/agent-resolver.mjs lines 34-36
const registryFileContents = readFileSync(AGENT_REGISTRY_PATH, 'utf8');
registry = JSON.parse(registryFileContents);
```

Every call to `resolveAgentFromSession` reads and parses the registry file from disk.

**Alternative:** Module-level singleton with `existsSync` on first call:
```javascript
let cachedRegistry = null;
function readAgentRegistry() {
  if (cachedRegistry !== null) return cachedRegistry;
  cachedRegistry = JSON.parse(readFileSync(AGENT_REGISTRY_PATH, 'utf8'));
  return cachedRegistry;
}
```

**Pros of current approach (no caching):** Registry changes take effect immediately without process restart. Simpler code. In a hook-per-event model, processes are short-lived — there is no meaningful session to cache across.

**Cons of current approach:** If multiple lib functions in one handler process call `resolveAgentFromSession`, each triggers a disk read and JSON parse. In practice, handlers will call it once per event, so this is not a performance concern. However, if `retryWithBackoff` wraps a function that includes `resolveAgentFromSession`, the registry is re-read on every retry — which is actually desirable if the registry was updated mid-retry sequence.

**Verdict:** Keep as-is. Read-on-every-call is the correct choice for a hook context where processes are short-lived and registry freshness matters more than performance. The file is small (a handful of agents) and `readFileSync` + `JSON.parse` on a small file is negligible.

---

## 4. Phase 1 Code Review Alignment

The table below maps each Phase 1 review finding to its Phase 02 outcome. REV-3.1 through REV-3.11 are the numbered findings from the Phase 1 code review. Items A, B, C are the non-REV items.

| Finding | Description | Phase 02 Outcome | Notes |
|---------|-------------|-----------------|-------|
| REV-3.1 | Redundant `date -u` calls in hook-event-logger.sh | Applied | `logger.mjs` calls `new Date().toISOString()` once per `appendJsonlEntry` invocation (line 33). Single capture pattern adopted. |
| REV-3.2 | `trap 'exit 0' ERR` scope too broad — covered stdin read | Not applicable | Phase 02 is Node.js lib — no bash trap. But the philosophy (protect caller, not stdin) informed the `logger.mjs` try/catch placement. |
| REV-3.3 | Shell injection via `execSync` template strings | Applied | `gateway.mjs` uses `execFileSync('openclaw', openclawArguments)` with an explicit argument array (lines 72-82). No string interpolation. |
| REV-3.4 | System prompt passed as unescaped shell argument | Not applicable | Phase 02 does not launch sessions. The `promptFilePath` in gateway is a file path passed as an argument to `readFileSync`, not to a shell. |
| REV-3.5 | `sleepSeconds` via `execSync('sleep N')` | Applied | `retry.mjs` uses `await new Promise((resolve) => setTimeout(resolve, delayMilliseconds))` (line 60). No shell sleep. |
| REV-3.6 | Custom 23-line argument parser reinventing `node:util parseArgs` | Not applicable | Phase 02 lib modules have no CLI argument parsing — they are importable functions. |
| REV-3.7 | `--dangerously-skip-permissions` hardcoded | Not applicable | Phase 02 does not launch Claude sessions. `gateway.mjs` wakes an existing session, not creates one. |
| REV-3.8 | `_comment_*` keys anti-pattern in JSON | Not applicable | Phase 02 adds no new config files. `config/SCHEMA.md` was established in Phase 01.1. |
| REV-3.9 | `package.json` missing `engines`, `bin`, `scripts`, `license` | Applied | Phase 01.1 added `engines`, `bin`, `license`, `scripts.check`. Phase 02 added `exports` field to package.json. No regression. |
| REV-3.10 | `.gitignore` missing `node_modules/`, `.env`, `*.lock` | Not applicable | Fixed in Phase 01.1; Phase 02 installed no new packages, gitignore remains correct. |
| REV-3.11 | SKILL.md missing `launch-session.mjs`; README mixes current/planned structure | Not applicable | Fixed in Phase 01.1. Phase 02 added lib/ files but did not update SKILL.md (deferred — see Section 5 gap). |
| Item A | `jq -cn` DRY violation in hook-event-logger.sh | Not applicable | The bash logger was not modified in Phase 02. The jq DRY violation remains as-is. `lib/logger.mjs` supersedes it eventually. |
| Item B | Cross-platform tension (PROJECT.md vs SKILL.md vs actual code) | Applied | Resolved in Phase 01.1 audit. Phase 02 is Node.js-only with `node:` built-ins — no platform-specific code added. |
| Item C | `default-system-prompt.md` is a stub | Not applicable | Still intentionally a stub. Phase 02 did not address agent system prompts — deferred to Phase 3+. |

**Summary:** Of the 14 items, 4 were applied or built upon in Phase 02, 9 were not applicable (already fixed, irrelevant to lib, or deferred by design), and 1 (Item A — jq DRY) remains unaddressed in bash and will be made irrelevant when the bash logger is retired.

---

## 5. Progress Toward Autonomous Driving Goal

**Goal:** "When Claude Code fires any hook event, the right agent wakes up with the right context and knows exactly which GSD slash command to type next."

### 5.1 Pieces Now in Place

| Piece | Module | Completeness |
|-------|--------|--------------|
| Hook event data extraction | `json-extractor.mjs` | Complete — handles valid/invalid JSON, missing fields, returns null safely |
| Session-to-agent mapping | `agent-resolver.mjs` | Complete — reads registry, handles disabled agents, unknown sessions |
| Gateway delivery | `gateway.mjs` | Complete — sends metadata + content + prompt to agent via `openclaw agent --session-id` |
| Retry on delivery failure | `retry.mjs` | Complete — exponential backoff with JSONL progress logging |
| Structured logging | `logger.mjs` | Complete — atomic JSONL appends, never throws |
| Single import entry point | `index.mjs` | Complete — all 5 functions from one import |

The foundational layer is done. A Phase 3 event handler can import from `lib/index.mjs` and, in roughly 20-30 lines, implement the full wake pipeline: extract session name from hook JSON → resolve agent → wake via gateway with retry.

### 5.2 Pieces Still Missing

**Event handlers (`events/*/handler.mjs`):** Not implemented. Each event type (Stop, AskUserQuestion, PreToolUse, PostToolUse, Notification) needs its own handler that reads stdin, extracts the right fields, and calls `wakeAgentViaGateway`. This is Phase 3 and Phase 4 work.

**Per-event prompt files (`events/*/prompt.md`):** Not created. The `wakeAgentViaGateway` function reads a prompt file at `promptFilePath` — but no prompt files exist yet. Phase 3 must create these to give agents the GSD slash command guidance they need.

**Hook registration (`.claude/settings.json`):** The Claude Code hook system must be configured to route events to the right handler scripts. No `.claude/settings.json` or equivalent hook registration has been created. Without this, events fire but reach no handler.

**TUI driver logic in prompts:** The end goal requires the agent to "know exactly which GSD slash command to type next" — this depends on the prompt files encoding the right slash command sequences, keystroke instructions, and context cues. The `wakeAgentViaGateway` architecture supports this (prompt file is fully configurable), but the prompt content itself must be written and tested.

**`tmux_session_name` extraction from hook env:** The hook handler must determine the current tmux session name. The resolver uses `session_name` to look up agents, but how a handler extracts the session name from its execution environment (`$TMUX`, `tmux display-message -p '#S'`, or from the hook JSON itself) has not been decided or implemented.

### 5.3 Are the Lib Abstractions at the Right Level?

The lib is at the right abstraction level for Phase 3 event handlers. The contract is clear:

```javascript
// hypothetical Phase 3 Stop event handler (events/stop/handler.mjs)
import { extractJsonField, resolveAgentFromSession, wakeAgentViaGateway, retryWithBackoff } from '../../lib/index.mjs';

const hookPayload = await readStdin();
const sessionName = extractJsonField(hookPayload, 'session_id'); // or from env
const agentConfig = resolveAgentFromSession(sessionName);

if (!agentConfig) process.exit(0); // Unmanaged session — silent skip

const lastAssistantMessage = extractJsonField(hookPayload, 'transcript_path'); // or similar

await retryWithBackoff(
  () => wakeAgentViaGateway({
    openclawSessionId: agentConfig.openclaw_session_id,
    messageContent: lastAssistantMessage,
    promptFilePath: new URL('./prompt.md', import.meta.url).pathname,
    eventMetadata: { eventType: 'Stop', sessionName, timestamp: new Date().toISOString() },
    sessionName,
  }),
  { maxAttempts: 3, operationLabel: 'wake-on-stop', sessionName },
);
```

This is readable, explicit, and testable. Each step is one function call from the lib. The handler's own code would be under 30 lines.

### 5.4 Risk Assessment for Phase 3

**Risk 1 — Hook JSON schema mismatch:** The Stop hook payload schema is not yet verified against `extractJsonField`'s top-level-only access. If the stop reason or session identifier is nested (`hook.session.name`), Phase 3 will need to extend `extractJsonField` before it can extract the value. This is low risk to discover (it surfaces on first test run) but requires the Phase 3 plan to include schema inspection.

**Risk 2 — `openclaw_session_id` availability:** `wakeAgentViaGateway` requires the agent's `openclaw_session_id`. This field must be present and correct in `config/agent-registry.json`. If the live OpenClaw session UUID changes (session rotation, restart), the registry becomes stale and delivery fails. There is no refresh or discovery mechanism in the current lib — the registry is treated as static. This will surface during Phase 3 end-to-end testing.

**Risk 3 — Retry defaults in hook context:** As noted in Section 3.5, the default 10-attempt/5s-base retry sequence could hold a hook process alive for 42 minutes. Phase 3 must document and deliberately override these defaults (e.g., `{ maxAttempts: 3, initialDelayMilliseconds: 2000 }`).

**Risk 4 — `promptFilePath` must be absolute:** `wakeAgentViaGateway` passes `promptFilePath` directly to `readFileSync`. If a handler passes a relative path, it is relative to the Node.js process CWD at runtime — which may not be the skill root. Phase 3 handlers must use `new URL('./prompt.md', import.meta.url).pathname` or resolve via `SKILL_ROOT` to guarantee an absolute path.

---

## 6. Scores

### Code Quality: 5/5

Clean, substantive, readable. All 6 files have meaningful implementations (not stubs). Line counts are appropriate for the complexity: `logger.mjs` at 51 lines, `json-extractor.mjs` at 55 lines, `retry.mjs` at 63 lines, `agent-resolver.mjs` at 70 lines, `gateway.mjs` at 103 lines, `index.mjs` at 14 lines. No dead code, no commented-out blocks, no TODOs. JSDoc is accurate and complete. The verification score (13/13) and UAT score (6/6) match code quality claims.

### DRY/SRP: 5/5

SRP is applied at every level: one file per concern, one export per file, one responsibility per function. DRY is demonstrated by the shared `appendJsonlEntry` import across all four dependent modules — no logging duplication. The `SKILL_ROOT` computation appears twice (a minor violation noted in Section 3.3) but this is a low-impact pattern that is idiomatic in ESM contexts. No business logic is repeated across files.

### Naming Conventions: 5/5

Full CLAUDE.md compliance. Zero abbreviations. Every function and variable name reads as a plain English phrase. Examples: `logFilePrefix`, `openclawArguments`, `registryFileContents`, `entryTimestamp`, `matchingAgent`. This is the naming standard the project should maintain into Phase 3 and beyond.

### Error Handling: 4/5

The three-tier error philosophy (swallow / return-null / throw) is coherent and appropriate. The gateway correctly logs before re-throwing so callers always have a JSONL trace. Deduction for: the logger's bare `catch {}` with no discriminated handling (disk full silently indistinguishable from expected I/O failure), and `wakeAgentViaGateway` not validating the `eventMetadata` parameter structure (a missing `eventMetadata.eventType` would produce `undefined` in the combined message string without an error).

### Security: 5/5

No shell injection anywhere. `gateway.mjs` uses `execFileSync` with an argument array — the lesson from Phase 01.1's REV-3.3 finding was fully applied. No user-controlled strings are interpolated into commands. Registry reads use `readFileSync` directly (not a shell command). No secrets are logged to JSONL. The only external call is to the `openclaw` binary via argument array — no exposure surface.

### Future-Proofing: 4/5

The lib is architected to support Phase 3-5 event handlers without refactoring the existing modules. The retry utility, resolver, gateway, and logger can each be used independently or in combination. Deduction for: `extractJsonField` top-level-only limitation (will require extension for PostToolUse nested payloads), retry defaults that may not suit hook contexts, and the `SKILL_ROOT` duplication that will become a depth-counting problem when event handlers at `events/stop/` depth need it. None of these require retrofitting the current lib — they are extensions or default changes.

---

## 7. Summary Table

| File | Key Strength | Key Concern | Recommendation |
|------|-------------|-------------|----------------|
| `lib/logger.mjs` | O_APPEND atomicity; single timestamp capture; never throws | Bare `catch {}` swallows disk-full silently — no diagnostic signal | Add discriminated error handling for unexpected errors (stderr fallback); low priority |
| `lib/json-extractor.mjs` | Guard clauses for all three failure paths; warning log per failure | Top-level field access only — nested paths like `tool_use.name` not supported | Extend with dot-notation path support before Phase 4 (PostToolUse) |
| `lib/retry.mjs` | Clean exponential backoff; JSONL progress logging; caller-configurable | Default 10 attempts/5s base = 42min max hold — too long for hook context | Change defaults to 3 attempts/2s base; document in JSDoc |
| `lib/agent-resolver.mjs` | Six guard clauses; silent null for unmanaged sessions; reads fresh registry | `SKILL_ROOT` duplicated from logger; re-reads file on every call | Acceptable now; add `lib/paths.mjs` when first event handler needs SKILL_ROOT |
| `lib/gateway.mjs` | `execFileSync` arg array (no injection); dual-path logging; 120s timeout | Hardcoded markdown template — no flexibility for event-type-specific formats; `eventMetadata` fields not validated | Add optional `eventMetadata` validation; extend message format only when a new event type requires it |
| `lib/index.mjs` | 14-line pure re-export barrel; no logic; no side effects | No named re-export documentation in file (relies on JSDoc in individual modules) | Keep as-is; add comment block if the export list grows beyond 8-10 functions |

---

*Review completed: 2026-02-20*
*Phase 02 verification score: 13/13 must-haves verified*
*UAT score: 6/6 tests passed*
*Commits reviewed: 9e01e54, 271cd63, 28a4d23, 98c4806, e6996cf, aa468f6*
