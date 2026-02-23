---
phase: quick-23
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - events/stop/event_stop.mjs
  - events/session_start/event_session_start.mjs
  - events/user_prompt_submit/event_user_prompt_submit.mjs
  - events/pre_tool_use/event_pre_tool_use.mjs
  - events/post_tool_use/event_post_tool_use.mjs
autonomous: true
requirements: [QUICK-23]

must_haves:
  truths:
    - "Every hook handler invocation logs the full hookPayload once as a debug entry"
    - "Existing decision-level log entries remain unchanged"
    - "Domain handlers (handle_ask_user_question, handle_post_ask_user_question) do NOT get duplicate payload logs"
  artifacts:
    - path: "events/stop/event_stop.mjs"
      provides: "Raw payload log on line after destructure (line 28)"
      contains: "hook_payload: hookPayload"
    - path: "events/session_start/event_session_start.mjs"
      provides: "Raw payload log on line after destructure (line 29)"
      contains: "hook_payload: hookPayload"
    - path: "events/user_prompt_submit/event_user_prompt_submit.mjs"
      provides: "Raw payload log on line after destructure (line 35)"
      contains: "hook_payload: hookPayload"
    - path: "events/pre_tool_use/event_pre_tool_use.mjs"
      provides: "Raw payload log on line after destructure (line 18)"
      contains: "hook_payload: hookPayload"
    - path: "events/post_tool_use/event_post_tool_use.mjs"
      provides: "Raw payload log on line after destructure (line 18)"
      contains: "hook_payload: hookPayload"
  key_links: []
---

<objective>
Add a single "raw event received" debug log entry at the top of each hook handler's main(), right after readHookContext() succeeds and the hookPayload is destructured. This captures the full Claude Code hook payload for debugging without duplicating it across every decision log entry.

Purpose: Full hook payloads enable post-hoc debugging of handler behavior without modifying the existing sparse decision logs.
Output: 5 event handler files each with one new appendJsonlEntry call containing hook_payload.
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
@events/post_tool_use/event_post_tool_use.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add hook_payload debug log to all 5 entry point handlers</name>
  <files>
    events/stop/event_stop.mjs
    events/session_start/event_session_start.mjs
    events/user_prompt_submit/event_user_prompt_submit.mjs
    events/pre_tool_use/event_pre_tool_use.mjs
    events/post_tool_use/event_post_tool_use.mjs
  </files>
  <action>
In each of the 5 files, add ONE appendJsonlEntry call immediately after the `const { hookPayload, sessionName, resolvedAgent } = hookContext;` destructure line. The new log entry goes BEFORE any other logic (guards, dispatching, etc.).

The pattern for each file (only the `source` value changes):

```javascript
appendJsonlEntry({
  level: 'debug',
  source: '<source_name>',
  message: 'Hook payload received',
  session: sessionName,
  hook_payload: hookPayload,
}, sessionName);
```

Source values by file:
- event_stop.mjs: source = 'event_stop'
- event_session_start.mjs: source = 'event_session_start'
- event_user_prompt_submit.mjs: source = 'event_user_prompt_submit'
- event_pre_tool_use.mjs: source = 'event_pre_tool_use'
- event_post_tool_use.mjs: source = 'event_post_tool_use'

Do NOT modify any existing log entries. Do NOT add payload logs to domain handlers (handle_ask_user_question.mjs, handle_post_ask_user_question.mjs) or non-hook files (tui-driver.mjs). Do NOT add payload logs to bin/ scripts.

Each file already imports appendJsonlEntry from lib/index.mjs, so no new imports are needed.
  </action>
  <verify>
    <automated>cd /home/forge/.openclaw/workspace/skills/gsd-code-skill && node -e "
const files = [
  'events/stop/event_stop.mjs',
  'events/session_start/event_session_start.mjs',
  'events/user_prompt_submit/event_user_prompt_submit.mjs',
  'events/pre_tool_use/event_pre_tool_use.mjs',
  'events/post_tool_use/event_post_tool_use.mjs',
];
const { readFileSync } = require('fs');
let allPassed = true;
for (const filePath of files) {
  const content = readFileSync(filePath, 'utf8');
  if (!content.includes('hook_payload: hookPayload')) {
    console.error('FAIL: missing hook_payload in ' + filePath);
    allPassed = false;
  }
  const matches = content.match(/hook_payload: hookPayload/g);
  if (matches && matches.length > 1) {
    console.error('FAIL: duplicate hook_payload in ' + filePath);
    allPassed = false;
  }
  if (!content.includes(\"message: 'Hook payload received'\")) {
    console.error('FAIL: missing message in ' + filePath);
    allPassed = false;
  }
}
if (allPassed) console.log('PASS: all 5 handlers have exactly one hook_payload log entry');
else process.exit(1);
"</automated>
    <manual>Inspect each file to confirm the new log line is placed immediately after the hookContext destructure, before any handler logic.</manual>
  </verify>
  <done>All 5 entry point handlers contain exactly one appendJsonlEntry call with hook_payload: hookPayload, placed right after readHookContext destructure. No domain handlers or non-hook files are modified. All existing log entries are untouched.</done>
</task>

</tasks>

<verification>
- Each of the 5 files has exactly one `hook_payload: hookPayload` entry (grep count = 1 per file)
- No domain handler files (handle_ask_user_question.mjs, handle_post_ask_user_question.mjs) contain hook_payload logs
- All files still parse as valid JavaScript: `node --check events/*/event_*.mjs`
</verification>

<success_criteria>
- 5 handler files modified, each with one new debug-level log line
- 0 domain handler files modified
- All files pass `node --check` syntax validation
</success_criteria>

<output>
After completion, create `.planning/quick/23-add-full-hookpayload-to-all-event-handle/23-SUMMARY.md`
</output>
