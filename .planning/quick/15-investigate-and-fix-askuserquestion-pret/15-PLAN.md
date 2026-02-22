---
phase: quick-15
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - /home/forge/.claude/settings.json
  - /home/forge/.openclaw/workspace/skills/gsd-code-skill/config/agent-registry.json
  - /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/hook-event-logger.sh
autonomous: true
requirements: [REG-02]
must_haves:
  truths:
    - "PreToolUse(AskUserQuestion) hook fires event_pre_tool_use.mjs when Claude Code invokes AskUserQuestion"
    - "PostToolUse(AskUserQuestion) hook fires event_post_tool_use.mjs when Claude Code completes AskUserQuestion"
    - "wakeAgentWithRetry can deliver to the warden agent via a real openclaw_session_id"
    - "hook-event-logger.sh uses session_id from JSON stdin (not tmux display-message) for log file naming"
  artifacts:
    - path: "/home/forge/.claude/settings.json"
      provides: "PreToolUse and PostToolUse handler registrations with AskUserQuestion matcher"
      contains: "event_pre_tool_use.mjs"
    - path: "/home/forge/.openclaw/workspace/skills/gsd-code-skill/config/agent-registry.json"
      provides: "Real openclaw_session_id for warden agent"
    - path: "/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/hook-event-logger.sh"
      provides: "Cross-session-safe log file naming using session_id from stdin JSON"
  key_links:
    - from: "/home/forge/.claude/settings.json"
      to: "events/pre_tool_use/event_pre_tool_use.mjs"
      via: "PreToolUse hook entry with matcher AskUserQuestion"
      pattern: "matcher.*AskUserQuestion"
    - from: "/home/forge/.claude/settings.json"
      to: "events/post_tool_use/event_post_tool_use.mjs"
      via: "PostToolUse hook entry with matcher AskUserQuestion"
      pattern: "matcher.*AskUserQuestion"
---

<objective>
Wire the Phase 4 AskUserQuestion handlers into production by fixing three deployment gaps: register PreToolUse and PostToolUse handlers in settings.json, replace the TODO placeholder in agent-registry.json with a real openclaw_session_id, and fix cross-session log bleeding in hook-event-logger.sh.

Purpose: Phase 4 code is complete and verified (9/9 must-haves) but never executes because the hooks are not registered and the gateway delivery target is a placeholder.
Output: Live AskUserQuestion lifecycle — hooks fire, agent gets woken, TUI driver can submit answers.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@/home/forge/.claude/settings.json
@/home/forge/.openclaw/workspace/skills/gsd-code-skill/config/agent-registry.json
@/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/hook-event-logger.sh
@/home/forge/.openclaw/workspace/skills/gsd-code-skill/events/pre_tool_use/event_pre_tool_use.mjs
@/home/forge/.openclaw/workspace/skills/gsd-code-skill/events/post_tool_use/event_post_tool_use.mjs
@/home/forge/.openclaw/workspace/skills/gsd-code-skill/.planning/phases/04-askuserquestion-lifecycle-full-stack/04-RESEARCH.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Register AskUserQuestion handlers in settings.json and fix agent-registry placeholder</name>
  <files>/home/forge/.claude/settings.json, /home/forge/.openclaw/workspace/skills/gsd-code-skill/config/agent-registry.json</files>
  <action>
**settings.json — Add PreToolUse and PostToolUse handler entries:**

Read `/home/forge/.claude/settings.json`. For each of `PreToolUse` and `PostToolUse`, the existing array has a single entry (hook-event-logger.sh). Add a SECOND entry to each array with the `AskUserQuestion` matcher. The existing logger entry stays (it has no matcher, so it fires on all tool uses). The new entries go AFTER the existing logger entries.

PreToolUse — append this object to the `PreToolUse` array:
```json
{
  "matcher": "AskUserQuestion",
  "hooks": [
    {
      "type": "command",
      "command": "node /home/forge/.openclaw/workspace/skills/gsd-code-skill/events/pre_tool_use/event_pre_tool_use.mjs",
      "timeout": 30
    }
  ]
}
```

PostToolUse — append this object to the `PostToolUse` array:
```json
{
  "matcher": "AskUserQuestion",
  "hooks": [
    {
      "type": "command",
      "command": "node /home/forge/.openclaw/workspace/skills/gsd-code-skill/events/post_tool_use/event_post_tool_use.mjs",
      "timeout": 30
    }
  ]
}
```

Timeout is 30 seconds (not 10) because these handlers do gateway delivery + question metadata I/O.

Do NOT touch any other hook arrays. Do NOT remove the existing hook-event-logger.sh entries.

**agent-registry.json — Replace TODO placeholder with real session ID:**

Read `config/agent-registry.json`. The warden agent has `"openclaw_session_id": "TODO-fill-in-real-session-id"`.

To get the real session ID, run:
```bash
openclaw sessions --json 2>/dev/null | jq -r '.[] | select(.name | test("warden"; "i")) | .id'
```

If that fails or returns empty, try:
```bash
openclaw sessions --json 2>/dev/null | jq -r '.[].id'
```
and list available sessions so the user can pick one.

If `openclaw` CLI is not available or returns no sessions, create a `checkpoint:human-action` note in the output asking the user to provide the warden session ID, but still complete the settings.json task.

Replace the TODO value with the real session ID. Do NOT change any other fields in agent-registry.json.
  </action>
  <verify>
Verify settings.json:
```bash
node -e "
const s = JSON.parse(require('fs').readFileSync('/home/forge/.claude/settings.json','utf8'));
const pre = s.hooks.PreToolUse;
const post = s.hooks.PostToolUse;
const preHasLogger = pre.some(e => !e.matcher && e.hooks?.[0]?.command?.includes('hook-event-logger'));
const preHasAsk = pre.some(e => e.matcher === 'AskUserQuestion' && e.hooks?.[0]?.command?.includes('event_pre_tool_use'));
const postHasLogger = post.some(e => !e.matcher && e.hooks?.[0]?.command?.includes('hook-event-logger'));
const postHasAsk = post.some(e => e.matcher === 'AskUserQuestion' && e.hooks?.[0]?.command?.includes('event_post_tool_use'));
console.log('PreToolUse logger:', preHasLogger, '| AskUserQuestion:', preHasAsk);
console.log('PostToolUse logger:', postHasLogger, '| AskUserQuestion:', postHasAsk);
if (!preHasLogger || !preHasAsk || !postHasLogger || !postHasAsk) process.exit(1);
console.log('PASS: All 4 entries present');
"
```

Verify agent-registry.json:
```bash
node -e "
const r = JSON.parse(require('fs').readFileSync('/home/forge/.openclaw/workspace/skills/gsd-code-skill/config/agent-registry.json','utf8'));
const warden = r.agents.find(a => a.agent_id === 'warden');
if (!warden) { console.log('FAIL: no warden agent'); process.exit(1); }
if (warden.openclaw_session_id.includes('TODO')) { console.log('FAIL: still has TODO placeholder'); process.exit(1); }
console.log('PASS: warden openclaw_session_id =', warden.openclaw_session_id);
"
```
  </verify>
  <done>
settings.json has PreToolUse and PostToolUse entries with matcher "AskUserQuestion" pointing to the correct .mjs handler scripts (alongside existing logger entries). agent-registry.json has a real openclaw_session_id for the warden agent (no TODO placeholder).
  </done>
</task>

<task type="auto">
  <name>Task 2: Fix cross-session log bleeding in hook-event-logger.sh</name>
  <files>/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/hook-event-logger.sh</files>
  <action>
The current logger uses `tmux display-message -p '#S'` for the tmux session name portion of the log file prefix. This is fine. But the `session_id` comes from the JSON stdin and is correct per invocation. The actual cross-session bleed risk is: when a `/clear` fires SessionEnd + SessionStart, the NEW session gets a new `session_id` in the JSON payload. The current code already uses `SESSION_ID` from JSON stdin (line 29), so the log file prefix WILL change correctly when session_id changes.

Re-examine the code: the `session_id` is read from `$STDIN_JSON` via jq on every invocation. Each hook invocation gets its own stdin with the current session's ID. There is NO cross-session bleeding in the current implementation — the session_id is NOT cached or inherited from a parent process.

However, there IS a subtle issue: `tmux display-message -p '#S'` runs in the HOOK PROCESS context, not in the tmux session context. When Claude Code spawns the hook as a child process, `$TMUX` env var may or may not be set depending on how Claude Code launches hooks.

Fix: Make the tmux session name resolution more robust by also checking the `session` field from the JSON payload (which the Node.js handlers already use via `readHookContext`). The `session` field in the hook JSON contains the session identifier that maps to agent-registry.json.

Update the tmux session name resolution (lines 41-52) as follows:

1. First try to get the session name from the JSON payload's `session` field: `SESSION_NAME=$(printf '%s' "$STDIN_JSON" | jq -r '.session // ""' 2>/dev/null || echo "")`
2. If that is empty, fall back to `tmux display-message -p '#S'`
3. Use `SESSION_NAME` (from JSON) instead of `TMUX_SESSION_NAME` (from tmux command) as the primary identifier

This makes the log file prefix deterministic from the JSON payload rather than dependent on the hook process's tmux context.

Replace lines 38-52 with:

```bash
# 5. Build unique log prefix from session name + Claude session_id
#    Primary source: JSON payload 'session' field (deterministic, no tmux dependency).
#    Fallback: tmux display-message (only if 'session' field is absent).
SESSION_NAME=$(printf '%s' "$STDIN_JSON" | jq -r '.session // ""' 2>/dev/null || echo "")
if [ -z "$SESSION_NAME" ]; then
  SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
fi
SHORT_SESSION_ID="${SESSION_ID:0:8}"

if [ -n "$SESSION_NAME" ] && [ -n "$SHORT_SESSION_ID" ]; then
  LOG_FILE_PREFIX="${SESSION_NAME}-${SHORT_SESSION_ID}"
elif [ -n "$SESSION_NAME" ]; then
  LOG_FILE_PREFIX="${SESSION_NAME}"
elif [ -n "$SHORT_SESSION_ID" ]; then
  LOG_FILE_PREFIX="session-${SHORT_SESSION_ID}"
else
  LOG_FILE_PREFIX="unknown-session"
fi
```

This ensures: (a) log files are named from the JSON payload's `session` field (same source the Node.js handlers use), (b) each `/clear` that produces a new `session_id` gets its own log file, (c) no dependency on the hook process having a valid `$TMUX` environment variable.
  </action>
  <verify>
```bash
# Verify the script parses correctly
bash -n /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/hook-event-logger.sh && echo "PASS: syntax ok"

# Verify it reads 'session' field from JSON
grep -q 'jq -r.*\.session' /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/hook-event-logger.sh && echo "PASS: reads session from JSON"

# Verify tmux is fallback, not primary
grep -n 'tmux display-message' /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/hook-event-logger.sh | head -1
# Should appear AFTER the jq '.session' line

# Smoke test with a mock payload
echo '{"hook_event_name":"PreToolUse","session_id":"abc12345-test","session":"agent_warden-test_session"}' | \
  bash /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/hook-event-logger.sh && echo "PASS: smoke test"

# Verify the log file was created with correct prefix
ls /home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/agent_warden-test_session-abc12345-raw-events.jsonl 2>/dev/null && echo "PASS: log file has correct prefix"
```
  </verify>
  <done>
hook-event-logger.sh resolves session name from JSON payload `session` field first (deterministic), falls back to tmux display-message only when JSON field is absent. Log file prefix uses session_id from each invocation's stdin, ensuring /clear boundaries produce separate log files. No cross-session log bleeding.
  </done>
</task>

</tasks>

<verification>
1. `settings.json` has PreToolUse array with both logger and AskUserQuestion handler entries
2. `settings.json` has PostToolUse array with both logger and AskUserQuestion handler entries
3. `agent-registry.json` warden entry has a real openclaw_session_id (not "TODO-fill-in-real-session-id")
4. `hook-event-logger.sh` reads `.session` from JSON stdin as primary session name source
5. `hook-event-logger.sh` passes bash -n syntax check and smoke test
</verification>

<success_criteria>
- PreToolUse(AskUserQuestion) hook invocation triggers event_pre_tool_use.mjs (verified by settings.json having the correct entry with matcher)
- PostToolUse(AskUserQuestion) hook invocation triggers event_post_tool_use.mjs (verified by settings.json having the correct entry with matcher)
- Gateway delivery has a valid target (agent-registry.json has real session ID)
- Logger creates separate log files per Claude Code session using JSON-sourced identifiers
</success_criteria>

<output>
After completion, create `.planning/quick/15-investigate-and-fix-askuserquestion-pret/15-SUMMARY.md`
</output>
