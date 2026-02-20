---
phase: quick-10
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/gateway.mjs
  - lib/index.mjs
  - events/stop/event_stop.mjs
  - events/session_start/event_session_start.mjs
  - events/user_prompt_submit/event_user_prompt_submit.mjs
autonomous: true
requirements: [QT10-01]
---

<objective>
Extract wakeAgentWithRetry helper — DRY refactor for 5 retryWithBackoff+gateway call sites across 3 handlers.

Purpose: Eliminate 60 lines of near-identical retryWithBackoff+wakeAgentViaGateway boilerplate. Each handler call becomes 1 line. Phase 04 handlers get retry from day one.
Output: 5 modified files, 0 new files.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@lib/gateway.mjs
@lib/index.mjs
@lib/retry.mjs
@events/stop/event_stop.mjs
@events/session_start/event_session_start.mjs
@events/user_prompt_submit/event_user_prompt_submit.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add wakeAgentWithRetry to gateway.mjs and re-export from index.mjs</name>
  <files>lib/gateway.mjs, lib/index.mjs</files>
  <action>
**1a. Add `wakeAgentWithRetry` to `lib/gateway.mjs`**

Add this function AFTER the existing `wakeAgentViaGateway` function. Import `retryWithBackoff` from `./retry.mjs` at the top.

```javascript
import { retryWithBackoff } from './retry.mjs';
```

```javascript
/**
 * Wake an agent via gateway with automatic retry on failure.
 *
 * Composes wakeAgentViaGateway with retryWithBackoff (3 attempts, 2s base).
 * Builds eventMetadata internally from the provided eventType and sessionName.
 *
 * @param {Object} params
 * @param {Object} params.resolvedAgent - Agent object with openclaw_session_id.
 * @param {string} params.messageContent - Content to deliver to the agent.
 * @param {string} params.promptFilePath - Absolute path to the prompt .md file.
 * @param {string} params.eventType - Hook event type (e.g. 'Stop', 'SessionStart').
 * @param {string} params.sessionName - tmux session name.
 * @returns {Promise<void>}
 */
export function wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType, sessionName }) {
  return retryWithBackoff(
    () => wakeAgentViaGateway({
      openclawSessionId: resolvedAgent.openclaw_session_id,
      messageContent,
      promptFilePath,
      eventMetadata: {
        eventType,
        sessionName,
        timestamp: new Date().toISOString(),
      },
      sessionName,
    }),
    { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: `wake-on-${eventType.toLowerCase()}`, sessionName },
  );
}
```

Update the module header comment to mention both exports.

**1b. Add re-export to `lib/index.mjs`**

Update the gateway re-export line from:
```javascript
export { wakeAgentViaGateway } from './gateway.mjs';
```
to:
```javascript
export { wakeAgentViaGateway, wakeAgentWithRetry } from './gateway.mjs';
```
  </action>
  <verify>
Run `node -e "import('./lib/gateway.mjs').then(m => console.log(typeof m.wakeAgentWithRetry))"` — should print `function`.
Run `node -e "import('./lib/index.mjs').then(m => console.log(typeof m.wakeAgentWithRetry))"` — should print `function`.
  </verify>
  <done>
`wakeAgentWithRetry` exported from gateway.mjs and re-exported from index.mjs. Raw `wakeAgentViaGateway` unchanged and still available.
  </done>
</task>

<task type="auto">
  <name>Task 2: Replace all 5 retryWithBackoff+wakeAgentViaGateway call sites with wakeAgentWithRetry</name>
  <files>events/stop/event_stop.mjs, events/session_start/event_session_start.mjs, events/user_prompt_submit/event_user_prompt_submit.mjs</files>
  <action>
**2a. event_stop.mjs** — 2 call sites

Replace imports: remove `retryWithBackoff` and `wakeAgentViaGateway`, add `wakeAgentWithRetry`.

Call site 1 (queue-complete, lines 54-67): Replace 12-line block with:
```javascript
await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'Stop', sessionName });
```

Call site 2 (fresh-wake, lines 95-108): Replace 12-line block with:
```javascript
await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'Stop', sessionName });
```

**2b. event_session_start.mjs** — 2 call sites

Replace imports: remove `retryWithBackoff` and `wakeAgentViaGateway`, add `wakeAgentWithRetry`.

Call site 1 (queue-complete on clear, lines 45-58): Replace with:
```javascript
await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'SessionStart', sessionName });
```

Call site 2 (stale archive, lines 70-83): Replace with:
```javascript
await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'SessionStart', sessionName });
```

**2c. event_user_prompt_submit.mjs** — 1 call site

Replace imports: remove `retryWithBackoff` and `wakeAgentViaGateway`, add `wakeAgentWithRetry`.

Call site 1 (queue cancel, lines 46-59): Replace with:
```javascript
await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'UserPromptSubmit', sessionName });
```
  </action>
  <verify>
Run `node --check events/stop/event_stop.mjs` — must pass.
Run `node --check events/session_start/event_session_start.mjs` — must pass.
Run `node --check events/user_prompt_submit/event_user_prompt_submit.mjs` — must pass.
Grep `retryWithBackoff` in events/ — should return zero matches (moved to gateway.mjs).
Grep `wakeAgentViaGateway` in events/ — should return zero matches (replaced by wakeAgentWithRetry).
Grep `wakeAgentWithRetry` in events/ — should return 5 matches (one per call site).
  </verify>
  <done>
All 5 call sites replaced. No handler imports `retryWithBackoff` or `wakeAgentViaGateway` directly — they use `wakeAgentWithRetry` which provides both.
  </done>
</task>

</tasks>

<verification>
1. `node --check lib/gateway.mjs` passes
2. `node --check events/stop/event_stop.mjs` passes
3. `node --check events/session_start/event_session_start.mjs` passes
4. `node --check events/user_prompt_submit/event_user_prompt_submit.mjs` passes
5. Grep `retryWithBackoff` in events/ returns zero matches
6. Grep `wakeAgentViaGateway` in events/ returns zero matches
7. Grep `wakeAgentWithRetry` in events/ returns exactly 5 matches
</verification>

<success_criteria>
60 lines of duplicated retryWithBackoff+wakeAgentViaGateway boilerplate replaced by 5 one-line calls to wakeAgentWithRetry. Helper lives in gateway.mjs alongside the raw function. All handlers pass syntax check. retryWithBackoff is no longer imported in any handler.
</success_criteria>

<output>
After completion, create `.planning/quick/10-extract-wakeagentwithretry-helper-dry-re/10-SUMMARY.md`
</output>
