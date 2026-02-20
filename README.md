# gsd-code-skill

v4.0 event-driven hook system for Claude Code agent lifecycle management. Each hook event is handled by a dedicated Node.js handler with its own prompt template.

## Status

v4.0 is under construction. The v1-v3 bash hook system has been removed. New event handlers are being built incrementally, one event at a time, full-stack (handler + prompt + integration test) before moving to the next.

## Current Structure

```
bin/              Executable scripts
  hook-event-logger.sh    Universal debug logger for all hook events
  launch-session.mjs      Tmux session launcher for registered agents
config/           Configuration files
  agent-registry.json     Agent registry (gitignored — contains secrets)
  agent-registry.example.json  Example registry (committed — documentation)
  default-system-prompt.md     Default system prompt for launched agents
  SCHEMA.md               Agent registry field documentation
logs/             Per-session log files (gitignored)
```

## Planned Structure (Phase 2+)

The following directories will be created in subsequent phases:

```
lib/              Shared Node.js library (agent registry, delivery, logging)
events/           One folder per Claude Code hook event
  stop/             event_stop.js, prompt_stop.md, tui_driver_stop.js
  pre_tool_use/     Subfolder per tool type
    ask_user_question/  event, prompt, tui driver
  post_tool_use/    Subfolder per tool type
    ask_user_question/  event, prompt
```
