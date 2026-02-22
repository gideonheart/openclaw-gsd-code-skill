---
phase: quick-16
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - bin/rotate-session.mjs
  - config/agent-registry.example.json
  - config/SCHEMA.md
autonomous: true
requirements: [QUICK-16]

must_haves:
  truths:
    - "Running rotate-session.mjs <agent-id> replaces the agent's openclaw_session_id with a new UUID"
    - "The old session ID is preserved in session_history with created_at and rotated_at timestamps"
    - "The registry file is written atomically (tmp + rename) to prevent corruption"
    - "SCHEMA.md documents session_history and all its sub-fields"
    - "agent-registry.example.json shows the session_history array structure"
  artifacts:
    - path: "bin/rotate-session.mjs"
      provides: "CLI script for session rotation"
      min_lines: 80
    - path: "config/agent-registry.example.json"
      provides: "Example config with session_history field"
      contains: "session_history"
    - path: "config/SCHEMA.md"
      provides: "Schema docs with session_history table"
      contains: "session_history"
  key_links:
    - from: "bin/rotate-session.mjs"
      to: "config/agent-registry.json"
      via: "readFileSync + atomic write (tmp + rename)"
      pattern: "renameSync"
---

<objective>
Add session rotation capability to the agent registry. Creates a CLI script that swaps an agent's openclaw_session_id for a fresh UUID while archiving the old ID with timestamps into a session_history array. Updates schema docs and example config.

Purpose: When starting fresh Claude Code sessions for an agent, the old session ID becomes stale. This script automates rotation and preserves history for reviewing past sessions.
Output: bin/rotate-session.mjs (executable CLI), updated config/agent-registry.example.json, updated config/SCHEMA.md
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@config/agent-registry.example.json
@config/SCHEMA.md
@bin/launch-session.mjs
@lib/paths.mjs
@lib/agent-resolver.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create bin/rotate-session.mjs CLI script</name>
  <files>bin/rotate-session.mjs</files>
  <action>
Create `bin/rotate-session.mjs` as an executable Node.js ESM CLI script (shebang: `#!/usr/bin/env node`).

Follow the exact patterns from `bin/launch-session.mjs`:
- Compute SKILL_ROOT via `dirname(dirname(fileURLToPath(import.meta.url)))` (bin scripts compute their own, they do NOT import from lib/paths.mjs per decision 02.1-01)
- Use `parseArgs` from `node:util` for CLI argument parsing
- Use `readFileSync`, `writeFileSync`, `renameSync` from `node:fs`
- Use `resolve` from `node:path`
- Use `crypto.randomUUID()` from `node:crypto` for new session ID
- logWithTimestamp helper like launch-session.mjs uses

**CLI interface:**
```
Usage: node bin/rotate-session.mjs <agent-id> [--label <text>]

Arguments:
  agent-id         ID of the agent whose session to rotate
  --label <text>   Optional label/reason for the rotation
  --help           Show this help message
```

**Core logic — isolated into SRP functions:**

1. `parseCommandLineArguments(rawArguments)` — parse args, return { positionalArguments, namedArguments }
2. `readAgentRegistry()` — read and parse config/agent-registry.json, throw if missing/invalid (same pattern as launch-session.mjs)
3. `findAgentByIdentifier(registry, agentIdentifier)` — find agent, throw if not found (does NOT check enabled — rotating disabled agents is valid)
4. `buildSessionHistoryEntry(oldSessionId, agentIdentifier, label)` — create the history entry object:
   ```json
   {
     "session_id": "<old-uuid>",
     "session_file": "/home/forge/.openclaw/agents/<agent_id>/sessions/<old-uuid>.jsonl",
     "rotated_at": "<ISO timestamp>",
     "label": "<text or null — omit key entirely if null>"
   }
   ```
   The `session_file` is the absolute path to the OpenClaw session JSONL file. This path is Ctrl+Click-able in terminals. Built from pattern: `/home/forge/.openclaw/agents/{agent_id}/sessions/{session_id}.jsonl`.
   NOTE: Use `rotated_at` only (no `created_at`). We do not know when the old session was created — the registry does not track creation timestamps. Including a fabricated value would be dishonest. The `rotated_at` timestamp is sufficient for history purposes.
5. `writeRegistryAtomically(registry)` — JSON.stringify with 2-space indent, write to tmp file (same directory, `.tmp` suffix), then renameSync over the original. This is the established atomic write pattern from this project.
6. `main()` — orchestrates: parse args, read registry, find agent, archive old ID to session_history, generate new UUID, write back, print summary.

**session_history behavior:**
- Initialize `agent.session_history = agent.session_history || []` if not present
- Push new entry to the END of the array (chronological order, newest last)
- Omit the `label` key entirely from the entry when label is null/undefined (do not store `"label": null`)

**stdout output after successful rotation:**
```
[ISO] Rotated session for agent: warden
[ISO]   Old: 0ab5ef5c-c3ba-4f49-8265-4129b3c36a59
[ISO]   New: a1b2c3d4-e5f6-7890-abcd-ef1234567890
[ISO]   History: 3 entries
[ISO]   Old session file: /home/forge/.openclaw/agents/warden/sessions/0ab5ef5c-c3ba-4f49-8265-4129b3c36a59.jsonl
```

The session file path follows the pattern `/home/forge/.openclaw/agents/{agent_id}/sessions/{session_id}.jsonl`. This provides a clickable Ctrl+Click link in the terminal to review the old session's conversation history.

**Error handling:**
- Missing agent-id argument: print usage and exit 1
- Registry file missing: throw with copy instructions (same as launch-session.mjs)
- Agent not found: throw listing known agent IDs (same as launch-session.mjs)
- JSON parse failure: throw with message
- Write failure: let it bubble (Node.js default stack trace is sufficient)

After creating the file, run `chmod +x bin/rotate-session.mjs`.
  </action>
  <verify>
Run `node bin/rotate-session.mjs --help` and confirm usage text prints.
Run `node -e "import('./bin/rotate-session.mjs')" 2>&1` to confirm no import/syntax errors (will show usage error since no agent-id, which is fine).
Verify shebang and executable bit: `head -1 bin/rotate-session.mjs` and `test -x bin/rotate-session.mjs`.
  </verify>
  <done>bin/rotate-session.mjs exists, is executable, parses args, reads registry, archives old session_id to session_history array, generates new UUID, writes atomically, prints summary with clickable review link.</done>
</task>

<task type="auto">
  <name>Task 2: Update example config and schema documentation</name>
  <files>config/agent-registry.example.json, config/SCHEMA.md</files>
  <action>
**agent-registry.example.json:**
Add `session_history` array to the first agent (gideon) with one example entry showing the structure. Leave the second agent (warden) WITHOUT session_history to show it is optional.

```json
{
  "agents": [
    {
      "agent_id": "gideon",
      "enabled": true,
      "session_name": "gideon-main",
      "working_directory": "/home/forge/.openclaw/workspace",
      "openclaw_session_id": "00000000-0000-0000-0000-000000000001",
      "system_prompt_file": "config/default-system-prompt.md",
      "skip_permissions": true,
      "session_history": [
        {
          "session_id": "00000000-0000-0000-0000-000000000000",
          "session_file": "/home/forge/.openclaw/agents/gideon/sessions/00000000-0000-0000-0000-000000000000.jsonl",
          "rotated_at": "2026-02-20T10:00:00Z",
          "label": "switched to v4.0 branch"
        }
      ]
    },
    {
      "agent_id": "warden",
      "enabled": true,
      "session_name": "warden-main",
      "working_directory": "/home/forge/my-project",
      "openclaw_session_id": "00000000-0000-0000-0000-000000000002",
      "system_prompt_file": "config/default-system-prompt.md",
      "skip_permissions": true
    }
  ]
}
```

**SCHEMA.md:**
Add `session_history` to the Agent Fields table:

| `session_history` | array | no | Array of previously-used session IDs, managed by `bin/rotate-session.mjs`. Each entry records the retired session ID and when it was rotated out. Newest entries at the end. |

Then add a new section below the existing Agent Fields table:

```markdown
## Session History Entry Fields

Each object in the `session_history` array has these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | yes | The retired OpenClaw session UUID that was replaced during rotation. |
| `session_file` | string | yes | Absolute path to the OpenClaw session JSONL file (`/home/forge/.openclaw/agents/{agent_id}/sessions/{session_id}.jsonl`). Ctrl+Click-able in terminals to review conversation history. |
| `rotated_at` | string | yes | ISO 8601 timestamp of when this session was retired and replaced with a new one. |
| `label` | string | no | Optional human-readable reason for the rotation (e.g., "switched to v4.0 branch"). Omitted when no label was provided. |
```
  </action>
  <verify>
Validate example JSON: `node -e "JSON.parse(require('fs').readFileSync('config/agent-registry.example.json', 'utf8')); console.log('Valid JSON')"`.
Confirm SCHEMA.md contains `session_history` in the Agent Fields table and the new Session History Entry Fields section.
  </verify>
  <done>agent-registry.example.json has session_history example on gideon (absent on warden). SCHEMA.md documents session_history in Agent Fields table and has dedicated Session History Entry Fields section with all 3 sub-fields documented.</done>
</task>

</tasks>

<verification>
1. `node bin/rotate-session.mjs --help` prints usage without errors
2. `node -e "JSON.parse(require('fs').readFileSync('config/agent-registry.example.json','utf8'))"` succeeds
3. SCHEMA.md has both `session_history` in Agent Fields table and the Session History Entry Fields section
4. bin/rotate-session.mjs has executable bit set
</verification>

<success_criteria>
- rotate-session.mjs creates new UUID, archives old one to session_history, writes atomically
- Example config shows the session_history structure on one agent
- Schema docs fully describe all fields including the nested entry object
- Script follows all codebase conventions: self-explanatory names, SRP functions, ESM patterns, no abbreviations
</success_criteria>

<output>
After completion, create `.planning/quick/16-add-session-rotation-to-agent-registry-r/16-SUMMARY.md`
</output>
