---
name: gsd-code-skill
description: Event-driven Claude Code hook system for GSD agent lifecycle management using Node.js handlers per event
metadata: {"openclaw":{"emoji":"🧭","os":["linux"],"requires":{"bins":["tmux","git","claude","jq","node"]}}}
---

# gsd-code-skill

v4.0 event-driven architecture. Each Claude Code hook event has its own folder under `events/` containing a Node.js handler and a prompt template. A shared Node.js library in `lib/` provides common utilities (agent resolution, gateway delivery, logging, retry, JSON extraction). No bash hook scripts — bash is only used where tmux interaction requires it.

## Scripts

- `bin/hook-event-logger.sh` — Universal debug logger for all Claude Code hook events. Reads stdin JSON payload and writes structured entries to per-session log files. Self-contained bootstrapping with no external library dependencies.
- `bin/launch-session.mjs` — Launch a Claude Code session in a named tmux session for a registered agent. Reads agent configuration from config/agent-registry.json, creates the tmux session, starts Claude Code with the agent's system prompt, and optionally sends an initial command after startup.
- `bin/tui-driver.mjs` — Generic TUI command driver. Creates a command queue and types the first slash command into a named tmux session. Hook-driven queue processor advances subsequent commands automatically. **Long content:** Commands are typed via tmux send-keys — newlines act as Enter and submit prematurely. For multiline content (task descriptions, prompts), write to `logs/prompts/<name>.md` and use `@file` reference syntax (e.g. `"/gsd:quick @logs/prompts/task-123.md"`). The directory is gitignored. Claude Code expands the reference at input time.

## Shared Library

Entry point: `lib/index.mjs` — 13 exports across 8 modules.

- `appendJsonlEntry` — Atomic JSONL logging with O_APPEND and discriminated error handling
- `extractJsonField` — Safe JSON field extraction from hook payloads
- `retryWithBackoff` — Exponential backoff retry (3 attempts, 2s base delay)
- `resolveAgentFromSession` — Session-to-agent lookup from agent-registry.json
- `wakeAgentViaGateway` — Send content and prompt to an agent via OpenClaw gateway
- `wakeAgentWithRetry` — Gateway delivery with automatic retry (3 attempts, 2s base)
- `typeCommandIntoTmuxSession` — Type slash command into tmux with Tab completion for /gsd:* commands
- `processQueueForHook` — Advance command queue when a hook fires (discriminated action returns)
- `cancelQueueForSession` — Cancel active queue when manual input is detected
- `cleanupStaleQueueForSession` — Archive stale queue on session startup
- `writeQueueFileAtomically` — Atomic queue file write (tmp + rename)
- `resolveQueueFilePath` — Build absolute path to session queue file
- `readHookContext` — Read stdin, parse JSON, resolve tmux session and agent (shared handler boilerplate)

## Configuration

- `config/agent-registry.json` — Agent registry mapping agent IDs to session config, working directories, and tmux session names
- `config/SCHEMA.md` — Agent registry field documentation
