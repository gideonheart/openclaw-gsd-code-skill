# gsd-code-skill

v4.0 event-driven hook system for Claude Code agent lifecycle management. Each hook event is handled by a dedicated Node.js handler with its own prompt template.

## Status

v4.0 is under construction. The v1-v3 bash hook system has been removed. New event handlers are being built incrementally, one event at a time, full-stack (handler + prompt + integration test) before moving to the next.

## Directory Structure

```
bin/          Bash utilities (hook-event-logger.sh)
lib/          Shared Node.js library (agent registry, delivery, logging)
events/       One folder per Claude Code hook event
  stop/         handler.js, prompt.md
  notification/ handler.js, prompt.md
  session-end/  handler.js, prompt.md
  pre-compact/  handler.js, prompt.md
  pre-tool-use/ handler.js, prompt.md
  post-tool-use/ handler.js, prompt.md
config/       agent-registry.json
logs/         Per-session log files (gitignored)
```
