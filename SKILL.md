---
name: gsd-code-skill
description: Event-driven Claude Code hook system for GSD agent lifecycle management using Node.js handlers per event
metadata: {"openclaw":{"emoji":"🧭","os":["linux"],"requires":{"bins":["tmux","git","claude","jq","node"]}}}
---

# gsd-code-skill

v4.0 event-driven architecture. Each Claude Code hook event has its own folder under `events/` containing a Node.js handler and a prompt template. A shared Node.js library in `lib/` provides common utilities. No bash hook scripts — bash is only used where tmux interaction requires it.

## Scripts

- `bin/hook-event-logger.sh` — Universal debug logger for all Claude Code hook events. Reads stdin JSON payload and writes structured entries to per-session log files. Self-contained bootstrapping with no external library dependencies.
- `bin/launch-session.mjs` — Launch a Claude Code session in a named tmux session for a registered agent. Reads agent configuration from config/agent-registry.json, creates the tmux session, starts Claude Code with the agent's system prompt, and optionally sends an initial command after startup.

## Configuration

- `config/agent-registry.json` — Agent registry mapping agent IDs to session config, working directories, and tmux session names
