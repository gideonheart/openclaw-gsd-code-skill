---
phase: quick-18
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/gateway.mjs
autonomous: true
requirements: []

must_haves:
  truths:
    - "openclaw agent CLI receives --agent flag with the correct agent_id on every wake call"
    - "wakeAgentWithRetry extracts agent_id from resolvedAgent and passes it through to wakeAgentViaGateway"
    - "All existing call sites continue to work without changes (backward compatible parameter addition)"
  artifacts:
    - path: "lib/gateway.mjs"
      provides: "--agent flag in openclaw CLI arguments"
      contains: "'--agent'"
  key_links:
    - from: "wakeAgentWithRetry"
      to: "wakeAgentViaGateway"
      via: "agentId parameter extracted from resolvedAgent.agent_id"
      pattern: "resolvedAgent\\.agent_id"
    - from: "wakeAgentViaGateway"
      to: "openclaw agent CLI"
      via: "--agent flag in openclawArguments array"
      pattern: "'--agent',\\s*agentId"
---

<objective>
Fix gateway.mjs to pass --agent flag to the openclaw agent CLI.

Purpose: Without --agent, openclaw cannot route to the correct agent when a rotated session UUID is unknown to it. The session lands under the "main" agent instead of the intended agent (e.g., warden). The agent_id is already available on the resolvedAgent object but was never threaded through to the CLI invocation.

Output: Updated lib/gateway.mjs with agentId parameter on wakeAgentViaGateway and automatic extraction in wakeAgentWithRetry.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@lib/gateway.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add agentId parameter to wakeAgentViaGateway and thread through wakeAgentWithRetry</name>
  <files>lib/gateway.mjs</files>
  <action>
**1a. Update wakeAgentViaGateway:**

Add `agentId` to the destructured wakeParameters object (after `openclawSessionId`).

Add a validation guard (same pattern as the existing guards):
```javascript
if (!agentId) {
  throw new Error('wakeAgentViaGateway: agentId is required');
}
```

Insert `'--agent', agentId` into the `openclawArguments` array, immediately after `'agent'` and before `'--session-id'`. The final array should be:
```javascript
const openclawArguments = [
  'agent',
  '--agent', agentId,
  '--session-id', openclawSessionId,
  '--message', combinedMessage,
];
```

Add `agent_id: agentId` to both JSONL log entries (the success and error appendJsonlEntry calls) alongside the existing `openclaw_session_id` field.

Update the JSDoc `@param` block to document the new `agentId` field:
```
 * @param {string} wakeParameters.agentId - The agent identifier (e.g., 'warden', 'gideon').
```

Update the module-level doc comment (line 7) from `openclaw agent --session-id` to `openclaw agent --agent --session-id`.

**1b. Update wakeAgentWithRetry:**

Extract `agent_id` from `resolvedAgent` and pass it as `agentId` to `wakeAgentViaGateway`. In the destructured call to wakeAgentViaGateway, add `agentId: resolvedAgent.agent_id` right before `openclawSessionId`:
```javascript
() => wakeAgentViaGateway({
  agentId: resolvedAgent.agent_id,
  openclawSessionId: resolvedAgent.openclaw_session_id,
  messageContent,
  ...
```

No changes needed to wakeAgentWithRetry's own parameter signature -- `resolvedAgent` already contains `agent_id`.

**Important:** Do NOT change any caller code in events/ -- the callers pass `resolvedAgent` to `wakeAgentWithRetry`, and `resolvedAgent` already has `agent_id`. This fix is entirely contained within lib/gateway.mjs.
  </action>
  <verify>
1. `node -e "import('./lib/gateway.mjs').then(m => console.log(typeof m.wakeAgentViaGateway, typeof m.wakeAgentWithRetry))"` prints `function function`
2. `node -e "import('./lib/gateway.mjs').then(m => { try { m.wakeAgentViaGateway({ openclawSessionId: 'x', messageContent: 'y', promptFilePath: 'z' }); } catch(e) { console.log(e.message); } })"` prints `wakeAgentViaGateway: agentId is required`
3. Grep for `'--agent'` in lib/gateway.mjs returns exactly 1 match
4. Grep for `resolvedAgent.agent_id` in lib/gateway.mjs returns exactly 1 match
5. Grep for `agent_id: agentId` in lib/gateway.mjs returns exactly 2 matches (success + error log entries)
  </verify>
  <done>
wakeAgentViaGateway includes '--agent' and agentId in the openclawArguments array. wakeAgentWithRetry extracts resolvedAgent.agent_id and passes it through. Both JSONL log entries include agent_id. Validation guard rejects calls missing agentId. No caller changes required.
  </done>
</task>

</tasks>

<verification>
1. `node --check lib/gateway.mjs` exits 0 (no syntax errors)
2. All 7 call sites in events/ still work unchanged (they pass resolvedAgent which has agent_id)
3. The openclaw CLI will now receive `--agent warden` (or whichever agent_id) on every wake delivery
</verification>

<success_criteria>
- `openclaw agent --agent {id} --session-id {uuid} --message {msg}` is the CLI invocation pattern
- agentId is required (throws if missing)
- agentId logged in both success and error JSONL entries
- Zero changes to caller code in events/
</success_criteria>

<output>
After completion, create `.planning/quick/18-fix-gateway-mjs-missing-agent-flag-pass-/18-SUMMARY.md`
</output>
