---
phase: quick-24
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - events/stop/event_stop.mjs
  - events/session_start/event_session_start.mjs
  - events/user_prompt_submit/event_user_prompt_submit.mjs
  - events/pre_tool_use/event_pre_tool_use.mjs
  - events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs
  - events/post_tool_use/event_post_tool_use.mjs
  - events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs
autonomous: true
requirements: [QUICK-24]

must_haves:
  truths:
    - "Every handler emits exactly ONE appendJsonlEntry call per execution — no scattered logs"
    - "The single trace entry contains hook_payload, decision_path, and outcome fields"
    - "Domain handlers (handle_ask_user_question, handle_post_ask_user_question) return structured result objects instead of logging internally"
    - "Early exits (guard clauses) still produce a trace entry via try/finally"
    - "No appendJsonlEntry calls exist in domain handler files"
  artifacts:
    - path: "events/stop/event_stop.mjs"
      provides: "Single-trace stop handler"
      contains: "finally"
    - path: "events/session_start/event_session_start.mjs"
      provides: "Single-trace session_start handler"
      contains: "finally"
    - path: "events/user_prompt_submit/event_user_prompt_submit.mjs"
      provides: "Single-trace user_prompt_submit handler"
      contains: "finally"
    - path: "events/pre_tool_use/event_pre_tool_use.mjs"
      provides: "Single-trace pre_tool_use router"
      contains: "finally"
    - path: "events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs"
      provides: "Domain handler returning structured result — no logging"
    - path: "events/post_tool_use/event_post_tool_use.mjs"
      provides: "Single-trace post_tool_use router"
      contains: "finally"
    - path: "events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs"
      provides: "Domain handler returning structured result — no logging"
  key_links:
    - from: "events/pre_tool_use/event_pre_tool_use.mjs"
      to: "events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs"
      via: "return value { decisionPath, outcome }"
      pattern: "const.*=.*await handleAskUserQuestion"
    - from: "events/post_tool_use/event_post_tool_use.mjs"
      to: "events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs"
      via: "return value { decisionPath, outcome }"
      pattern: "const.*=.*await handlePostAskUserQuestion"
---

<objective>
Replace all scattered appendJsonlEntry() calls across 5 event handlers and 2 domain handlers with a single comprehensive trace log entry per handler execution, using try/finally to guarantee the log fires on every exit path.

Purpose: Consolidate noisy multi-line debug logging into one structured trace entry that captures the full handler lifecycle: raw hookPayload, extracted values, decision path taken, and outcome — making JSONL logs scannable and debuggable.

Output: 7 modified handler files, each with exactly one appendJsonlEntry call (in the router's finally block), zero appendJsonlEntry calls in domain handlers.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@events/stop/event_stop.mjs
@events/session_start/event_session_start.mjs
@events/user_prompt_submit/event_user_prompt_submit.mjs
@events/pre_tool_use/event_pre_tool_use.mjs
@events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs
@events/post_tool_use/event_post_tool_use.mjs
@events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs
@lib/logger.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Consolidate standalone handler logs (stop, session_start, user_prompt_submit)</name>
  <files>
    events/stop/event_stop.mjs
    events/session_start/event_session_start.mjs
    events/user_prompt_submit/event_user_prompt_submit.mjs
  </files>
  <action>
For each of the 3 standalone handlers, apply this pattern:

1. Remove ALL existing appendJsonlEntry calls from the handler body.

2. After destructuring hookContext, declare a mutable handlerTrace object:
   ```javascript
   const handlerTrace = { decisionPath: null, outcome: {} };
   ```

3. Wrap the handler logic (everything after handlerTrace declaration, before process.exit(0)) in try/finally. The finally block contains the SINGLE appendJsonlEntry call:
   ```javascript
   try {
     // ... all handler logic, setting handlerTrace.decisionPath and handlerTrace.outcome ...
     // Replace process.exit(0) calls with `return` (the finally block runs, then main() ends, then the catch handler does NOT fire, and Node exits cleanly)
   } finally {
     appendJsonlEntry({
       level: 'info',
       source: '{handler_source}',
       message: `Handler complete: ${handlerTrace.decisionPath}`,
       session: sessionName,
       hook_payload: hookPayload,
       decision_path: handlerTrace.decisionPath,
       outcome: handlerTrace.outcome,
     }, sessionName);
   }
   ```

4. At each decision point (where an old appendJsonlEntry or process.exit was), set handlerTrace fields instead:

**event_stop.mjs** — 6 decision points become trace assignments:
- Line 34 reentrancy guard: `handlerTrace.decisionPath = 'reentrancy-guard'; return;`
- Line 41 no message: `handlerTrace.decisionPath = 'no-message'; return;`
- Line 48 queue advanced: `handlerTrace.decisionPath = 'queue-advanced'; return;`
- Line 52 queue complete: `handlerTrace.decisionPath = 'queue-complete'; handlerTrace.outcome = { summary: queueResult.summary }; return;` (AFTER the wakeAgentWithRetry call)
- Line 60 awaits mismatch: `handlerTrace.decisionPath = 'awaits-mismatch'; return;`
- Line 65 no active command: `handlerTrace.decisionPath = 'no-active-command'; return;`
- Fresh wake (bottom): `handlerTrace.decisionPath = 'fresh-wake'; handlerTrace.outcome = { suggested_commands: suggestedCommands };` (AFTER the wakeAgentWithRetry call, then falls through to finally)

Remove the `process.exit(0)` at line 93 — the function naturally returns and the outer `main().catch(...)` handles exit.

NOTE: Keep the very first `process.exit(0)` on line 27 (the `if (!hookContext)` guard) OUTSIDE the try/finally — that fires before hookContext exists, so there is nothing to trace.

**event_session_start.mjs** — 4 decision points:
- clear + awaits-mismatch: `handlerTrace.decisionPath = 'clear-awaits-mismatch'; return;`
- clear + queue-complete: `handlerTrace.decisionPath = 'clear-queue-complete'; handlerTrace.outcome = { summary: queueResult.summary }; return;`
- clear + advanced (implicit — queueResult.action is 'advanced'): `handlerTrace.decisionPath = 'clear-queue-advanced'; return;`
- clear + other queue actions: `handlerTrace.decisionPath = 'clear-other'; return;`

  For the `source === 'clear'` block: the current code checks `awaits-mismatch` and `queue-complete` with if statements, then calls `process.exit(0)`. Refactor to set decisionPath for each case. Add explicit handling for 'advanced' and a fallback for other queue actions. Then `return` after the clear block instead of process.exit.

- startup + stale queue: `handlerTrace.decisionPath = 'startup-stale-queue'; handlerTrace.outcome = { had_stale_queue: true }; return;`
- startup + clean: `handlerTrace.decisionPath = 'startup-clean'; return;`
- unhandled source: `handlerTrace.decisionPath = 'unhandled-source'; handlerTrace.outcome = { source }; return;`

**event_user_prompt_submit.mjs** — 4 decision points:
- TUI driver input: `handlerTrace.decisionPath = 'tui-driver-input'; return;`
- AskUserQuestion flow: `handlerTrace.decisionPath = 'ask-user-question-flow'; return;`
- No queue: `handlerTrace.decisionPath = 'no-queue'; return;`
- Queue cancelled: `handlerTrace.decisionPath = 'queue-cancelled'; handlerTrace.outcome = { completed_count: completedCount, total_count: totalCount, remaining_count: remainingCommands.length, remaining_commands: remainingCommands.map(queuedCommand => queuedCommand.command) }; return;`

5. The `extracted` field is NOT needed in the trace — the full `hook_payload` already contains all raw data. Decision path + outcome are the structured summary.

6. Keep the `main().catch(...)` error handler unchanged — it handles uncaught errors.
  </action>
  <verify>
    <automated>cd /home/forge/.openclaw/workspace/skills/gsd-code-skill && node -c events/stop/event_stop.mjs && node -c events/session_start/event_session_start.mjs && node -c events/user_prompt_submit/event_user_prompt_submit.mjs && echo "Syntax OK" && grep -c "appendJsonlEntry" events/stop/event_stop.mjs events/session_start/event_session_start.mjs events/user_prompt_submit/event_user_prompt_submit.mjs</automated>
    <manual>Each of the 3 files should show exactly 1 appendJsonlEntry call (in the finally block). Verify grep counts are all 1.</manual>
  </verify>
  <done>
    - event_stop.mjs: 6 appendJsonlEntry calls replaced with 1 in finally block, 6 decision paths set
    - event_session_start.mjs: 4 appendJsonlEntry calls replaced with 1 in finally block, 6 decision paths set
    - event_user_prompt_submit.mjs: 5 appendJsonlEntry calls replaced with 1 in finally block, 4 decision paths set
    - All 3 files pass syntax check (node -c)
    - No process.exit(0) calls remain inside the try block (only `return` statements)
    - The pre-hookContext guard `if (!hookContext) process.exit(0)` remains outside try/finally
  </done>
</task>

<task type="auto">
  <name>Task 2: Consolidate router+domain handler logs (pre_tool_use, post_tool_use) with return value refactor</name>
  <files>
    events/pre_tool_use/event_pre_tool_use.mjs
    events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs
    events/post_tool_use/event_post_tool_use.mjs
    events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs
  </files>
  <action>
These 2 routers delegate to domain handlers that currently log internally. The refactor requires TWO changes: (a) domain handlers return structured results instead of logging, (b) routers capture the return value and include it in their single trace entry.

**handle_ask_user_question.mjs (domain handler):**
1. Remove the `appendJsonlEntry` import from `../../../lib/index.mjs`.
2. Remove the appendJsonlEntry call at lines 45-52.
3. Change the function to return a structured result object:
   ```javascript
   return {
     decisionPath: 'ask-user-question',
     outcome: {
       tool_use_id: toolUseId,
       question_count: toolInput.questions.length,
     },
   };
   ```
4. Update the JSDoc @returns to `@returns {Promise<{decisionPath: string, outcome: Object}>}`.

**handle_post_ask_user_question.mjs (domain handler):**
1. Remove the `appendJsonlEntry` import from `../../../lib/index.mjs`.
2. Remove ALL 4 appendJsonlEntry calls (lines 46-51, 62-68, 78-84, 110-117).
3. At each decision point, return a structured result instead of logging + returning void:

   - No pending answer (line 45-56):
     ```javascript
     deleteQuestionMetadata(sessionName);
     return {
       decisionPath: 'ask-user-question-no-pending',
       outcome: { reason: 'No pending-answer file found' },
     };
     ```

   - Missing tool_response.answers (line 61-73):
     ```javascript
     deletePendingAnswer(sessionName);
     deleteQuestionMetadata(sessionName);
     return {
       decisionPath: 'ask-user-question-missing-response',
       outcome: { tool_use_id: pendingAnswer.tool_use_id, reason: 'Missing tool_response.answers' },
     };
     ```

   - Match (line 77-89):
     ```javascript
     deletePendingAnswer(sessionName);
     deleteQuestionMetadata(sessionName);
     return {
       decisionPath: 'ask-user-question-verified',
       outcome: { tool_use_id: pendingAnswer.tool_use_id },
     };
     ```

   - Mismatch (line 91-120):
     ```javascript
     // ... wakeAgentWithRetry call stays ...
     deletePendingAnswer(sessionName);
     deleteQuestionMetadata(sessionName);
     return {
       decisionPath: 'ask-user-question-mismatch',
       outcome: { tool_use_id: pendingAnswer.tool_use_id, reason: comparisonResult.reason },
     };
     ```

4. Update JSDoc @returns to `@returns {Promise<{decisionPath: string, outcome: Object}>}`.
5. Keep buildMismatchMessageContent and formatQuestionsForMismatchContext private functions unchanged.

**event_pre_tool_use.mjs (router):**
1. Remove ALL existing appendJsonlEntry calls (lines 20, 30-35).
2. Add handlerTrace + try/finally pattern (same as Task 1).
3. For the AskUserQuestion branch, capture the return value:
   ```javascript
   const domainResult = await handleAskUserQuestion({ hookPayload, sessionName, resolvedAgent });
   handlerTrace.decisionPath = domainResult.decisionPath;
   handlerTrace.outcome = domainResult.outcome;
   return;
   ```
4. For the no-handler fallback:
   ```javascript
   handlerTrace.decisionPath = 'no-handler';
   handlerTrace.outcome = { tool_name: toolName };
   return;
   ```
5. The finally block logs the single trace entry with `source: 'event_pre_tool_use'`.

**event_post_tool_use.mjs (router):**
1. Remove ALL existing appendJsonlEntry calls (lines 20, 30-35).
2. Add handlerTrace + try/finally pattern.
3. For the AskUserQuestion branch, capture the return value:
   ```javascript
   const domainResult = await handlePostAskUserQuestion({ hookPayload, sessionName, resolvedAgent });
   handlerTrace.decisionPath = domainResult.decisionPath;
   handlerTrace.outcome = domainResult.outcome;
   return;
   ```
4. For the no-handler fallback:
   ```javascript
   handlerTrace.decisionPath = 'no-handler';
   handlerTrace.outcome = { tool_name: toolName };
   return;
   ```
5. The finally block logs the single trace entry with `source: 'event_post_tool_use'`.

NOTE on level: The router's finally block should set level based on the decision path. For `ask-user-question-mismatch` and `ask-user-question-no-pending` and `ask-user-question-missing-response`, use `'warn'`. For all others use `'info'`. Example:
```javascript
const warnPaths = ['ask-user-question-mismatch', 'ask-user-question-no-pending', 'ask-user-question-missing-response'];
const logLevel = warnPaths.includes(handlerTrace.decisionPath) ? 'warn' : 'info';
```
  </action>
  <verify>
    <automated>cd /home/forge/.openclaw/workspace/skills/gsd-code-skill && node -c events/pre_tool_use/event_pre_tool_use.mjs && node -c events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs && node -c events/post_tool_use/event_post_tool_use.mjs && node -c events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs && echo "Syntax OK" && echo "--- appendJsonlEntry counts ---" && grep -c "appendJsonlEntry" events/pre_tool_use/event_pre_tool_use.mjs events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs events/post_tool_use/event_post_tool_use.mjs events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs</automated>
    <manual>Router files should each show 1 appendJsonlEntry call. Domain handler files should each show 0 appendJsonlEntry calls. Verify grep counts: routers=1, domain handlers=0.</manual>
  </verify>
  <done>
    - handle_ask_user_question.mjs: appendJsonlEntry removed, returns { decisionPath, outcome }
    - handle_post_ask_user_question.mjs: 4 appendJsonlEntry calls removed, returns { decisionPath, outcome } from all 4 paths
    - event_pre_tool_use.mjs: 2 appendJsonlEntry calls replaced with 1 in finally block, captures domain handler return
    - event_post_tool_use.mjs: 2 appendJsonlEntry calls replaced with 1 in finally block, captures domain handler return
    - All 4 files pass syntax check
    - Domain handlers have zero appendJsonlEntry calls and zero appendJsonlEntry imports
    - Router files have exactly 1 appendJsonlEntry call each (in finally block)
  </done>
</task>

</tasks>

<verification>
After both tasks complete, verify the consolidation across all 7 files:

1. Total appendJsonlEntry calls across all handler files should be exactly 5 (one per router/standalone handler):
   - events/stop/event_stop.mjs: 1
   - events/session_start/event_session_start.mjs: 1
   - events/user_prompt_submit/event_user_prompt_submit.mjs: 1
   - events/pre_tool_use/event_pre_tool_use.mjs: 1
   - events/post_tool_use/event_post_tool_use.mjs: 1
   - events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs: 0
   - events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs: 0

2. Every appendJsonlEntry call includes: hook_payload, decision_path, outcome fields.

3. No `process.exit(0)` calls inside try blocks — only `return` statements. The pre-hookContext guard stays outside.

4. lib/logger.mjs is NOT modified.
</verification>

<success_criteria>
- 24 scattered appendJsonlEntry calls reduced to exactly 5 (one per handler entry point)
- Each trace entry captures full hookPayload, decision_path string, and outcome object
- Domain handlers return structured { decisionPath, outcome } objects — zero internal logging
- All 7 files pass node -c syntax check
- try/finally pattern guarantees trace fires on every code path including early exits
</success_criteria>

<output>
After completion, create `.planning/quick/24-consolidate-handler-logs-into-single-end/24-SUMMARY.md`
</output>
