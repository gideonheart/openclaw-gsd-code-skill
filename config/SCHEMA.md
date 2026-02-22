# Agent Registry Schema

`config/agent-registry.json` maps agent identifiers to their session configuration, working directories, and launch settings. This file is gitignored because it contains secrets (openclaw_session_id values). Copy `agent-registry.example.json` and fill in real values.

## Top-Level Structure

```json
{
  "agents": [ ... ]
}
```

The only top-level key is `agents`, an array of agent configuration objects.

## Agent Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | yes | Unique identifier for this agent. Must match the agent name used in tmux session naming and OpenClaw routing. Examples: `gideon`, `warden`, `forge`. |
| `enabled` | boolean | yes | Set to `false` to disable all hook event handling for this agent without removing the entry. Attempting to launch a disabled agent will throw an error. |
| `session_name` | string | yes | The tmux session name where Claude Code runs for this agent. Used by `launch-session.mjs` to create the session and by event handlers to route events. |
| `working_directory` | string | yes | Absolute path to the agent's workspace. Claude Code will be launched in this directory. Can be overridden at launch time with `--workdir`. |
| `openclaw_session_id` | string | yes | OpenClaw session UUID used for gateway message delivery. Obtain from the OpenClaw dashboard or API. This is a secret value. |
| `system_prompt_file` | string | yes | Path to the system prompt markdown file, relative to the gsd-code-skill root directory. Used when launching Claude Code via `bin/launch-session.mjs`. |
| `skip_permissions` | boolean | no | When `true` (default if omitted), launches Claude Code with `--dangerously-skip-permissions` flag granting unrestricted filesystem and command access. Set to `false` to launch in standard permission mode. |
| `session_history` | array | no | Array of previously-used session IDs, managed by `bin/rotate-session.mjs`. Each entry records the retired session ID and when it was rotated out. Newest entries at the end. |

## Session History Entry Fields

Each object in the `session_history` array has these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | yes | The retired OpenClaw session UUID that was replaced during rotation. |
| `session_file` | string | yes | Absolute path to the OpenClaw session JSONL file (`/home/forge/.openclaw/agents/{agent_id}/sessions/{session_id}.jsonl`). Ctrl+Click-able in terminals to review conversation history. |
| `rotated_at` | string | yes | ISO 8601 timestamp of when this session was retired and replaced with a new one. |
| `label` | string | no | Optional human-readable reason for the rotation (e.g., "switched to v4.0 branch"). Omitted when no label was provided. |
