# gsd-code-skill

v4.0 event-driven hook system for Claude Code agent lifecycle management. Each hook event is handled by a dedicated Node.js handler with its own prompt template.

## Status

v4.0 is under construction. Phases 1–2 complete: v1-v3 bash hooks removed, shared Node.js library built and refactored. Next: Phase 3 (Stop event handler, full stack).

## Current Structure

```
bin/              Executable scripts
  hook-event-logger.sh    Universal debug logger for all hook events
  launch-session.mjs      Tmux session launcher for registered agents
lib/              Shared Node.js library
  index.mjs               Unified re-export entry point (5 exports)
  paths.mjs               Shared SKILL_ROOT constant
  logger.mjs              Atomic JSONL logging with discriminated error handling
  json-extractor.mjs      Safe JSON field extraction from hook payloads
  retry.mjs               Exponential backoff retry (3 attempts / 2s base)
  agent-resolver.mjs      Session-to-agent lookup from registry
  gateway.mjs             OpenClaw gateway delivery (wake agent with content + prompt)
config/           Configuration files
  agent-registry.json     Agent registry (gitignored — contains secrets)
  agent-registry.example.json  Example registry (committed — documentation)
  default-system-prompt.md     Default system prompt for launched agents
  SCHEMA.md               Agent registry field documentation
logs/             Per-session log files (gitignored)
```

## Planned Structure (Phase 3+)

The following directories will be created in subsequent phases:

```
events/           One folder per Claude Code hook event
  stop/             event_stop.js, prompt_stop.md, tui_driver_stop.js
  pre_tool_use/     Subfolder per tool type
    ask_user_question/  event, prompt, tui driver
  post_tool_use/    Subfolder per tool type
    ask_user_question/  event, prompt
```

## Hook Registration

To activate the Phase 3 event handlers, add the following entries to `~/.claude/settings.json` under the appropriate hook arrays. Replace `/absolute/path/to` with the absolute path to the skill's installation directory.

**Note:** The existing `hook-event-logger.sh` entries should remain alongside these — they provide debug logging. Phase 5 will deliver an automated registration script that manages these entries.

**Timeouts:** Stop and SessionStart at 30 seconds (queue processing + gateway delivery); UserPromptSubmit at 10 seconds (fires on every user input — must be fast).

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/events/stop/event_stop.mjs",
            "timeout": 30
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/events/session_start/event_session_start.mjs",
            "timeout": 30
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/events/user_prompt_submit/event_user_prompt_submit.mjs",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## Shared Library API

All exports available via `import { ... } from './lib/index.mjs'`:

| Export | Module | Purpose |
|--------|--------|---------|
| `appendJsonlEntry` | logger.mjs | Atomic JSONL log writes with O_APPEND |
| `extractJsonField` | json-extractor.mjs | Safe field extraction from hook JSON |
| `retryWithBackoff` | retry.mjs | Exponential backoff (3 attempts, 2s base) |
| `resolveAgentFromSession` | agent-resolver.mjs | Map tmux session to agent config |
| `wakeAgentViaGateway` | gateway.mjs | Send content + prompt to agent via OpenClaw |
