---
name: gsd-code-skill
description: Hook-driven GSD-only Claude Code sessions with deterministic recovery and event-based agent control
metadata: {"openclaw":{"emoji":"🧭","os":["linux"],"requires":{"bins":["tmux","git","claude","jq"]}}}
---

# gsd-code-skill

Launch Claude Code sessions constrained to GSD (Get Shit Done) workflow commands with event-driven hook control and automatic crash recovery.

## Quick Start

Three steps to launch a managed GSD session:

```bash
# 1. Configure agent entry in recovery registry (or let spawn.sh auto-create)
# Edit: skills/gsd-code-skill/config/recovery-registry.json

# 2. Register hooks in ~/.claude/settings.json (one-time setup)
skills/gsd-code-skill/scripts/register-hooks.sh

# 3. Spawn the session
skills/gsd-code-skill/scripts/spawn.sh <agent-name> <workdir> [first-command]
```

Example:

```bash
skills/gsd-code-skill/scripts/spawn.sh gideon /home/forge/.openclaw/workspace
```

The session starts in tmux with GSD system prompt, auto-detects the first command, and hooks handle all agent control.

## Lifecycle

Sessions follow this flow: **spawn** -> **hooks control session** -> **crash/reboot** -> **systemd timer** -> **recovery** -> **agents resume**.

Hooks fire on Claude Code events (Stop, Notification, SessionEnd, PreCompact) and send structured wake messages to the OpenClaw agent. The agent inspects session state, decides next action, and drives the TUI using `menu-driver.sh`.

After reboot or OOM, the systemd timer runs recovery, which restores tmux sessions, relaunches Claude Code, wakes OpenClaw agents, and resumes work automatically.

## Scripts

### Session Management

**spawn.sh** - Launch a new GSD Claude Code session in tmux

```bash
scripts/spawn.sh <agent-name> <workdir> [first-command]
```

Behavior:
- Auto-creates registry entry for unknown agents
- Composes system prompt (CLI override > registry agent prompt > default file)
- Auto-detects first command: `/init`, `/gsd:resume-work`, `/gsd:new-project @PRD.md`, or `/gsd:help`
- Resolves tmux session name conflicts with `-2` suffix

Example:

```bash
scripts/spawn.sh warden /home/forge/warden.kingdom.lv
```

Use `--help` for full options including `--system-prompt`.

**recover-openclaw-agents.sh** - Deterministic multi-agent recovery after reboot/OOM

```bash
scripts/recover-openclaw-agents.sh [--registry <path>] [--skip-session-id-sync]
```

Reads recovery registry, filters `enabled=true && auto_wake=true`, ensures tmux sessions exist, launches Claude Code if missing, sends deterministic wake instructions to OpenClaw agents. Silent on success, sends Telegram notification only on failures.

Use `--help` for full options.

**sync-recovery-registry-session-ids.sh** - Refresh OpenClaw session IDs in registry

```bash
scripts/sync-recovery-registry-session-ids.sh [--registry <path>] [--dry-run]
```

Syncs `openclaw_session_id` values from `/home/forge/.openclaw/agents/<agent_id>/sessions/sessions.json` by selecting the most recently updated `agent:<agent_id>:openai:*` session. Auto-run by recovery script unless `--skip-session-id-sync` is used.

Use `--help` for full options.

### Hooks

All hooks fire automatically on Claude Code events. For behavior specs, configuration, and edge cases, load `docs/hooks.md`.

**stop-hook.sh** - Fires when Claude finishes responding

**notification-idle-hook.sh** - Fires when Claude waits for user input (idle_prompt)

**notification-permission-hook.sh** - Fires on permission dialogs (permission_prompt)

**session-end-hook.sh** - Fires when Claude Code session terminates

**pre-compact-hook.sh** - Fires before Claude Code compacts context window

All hooks:
- Exit in <5ms for non-managed sessions
- Support async (default) or bidirectional mode via `hook_settings.hook_mode`
- Use three-tier fallback for configuration: per-agent > global > hardcoded defaults

### Utilities

**menu-driver.sh** - Deterministic tmux TUI helper for agent-driven menu navigation

```bash
scripts/menu-driver.sh <session> <action> [args]
```

Actions: `snapshot`, `enter`, `esc`, `clear_then <cmd>`, `choose <n>`, `type <text>`, `submit`

Example:

```bash
scripts/menu-driver.sh warden-main snapshot
scripts/menu-driver.sh warden-main choose 1
scripts/menu-driver.sh warden-main clear_then "/gsd:resume-work"
```

Use `--help` for full action list.

**register-hooks.sh** - Idempotent hook registration in ~/.claude/settings.json

```bash
scripts/register-hooks.sh
```

Registers all 5 hook events (Stop, Notification [idle_prompt + permission_prompt], SessionEnd, PreCompact) and removes obsolete `gsd-session-hook.sh` from SessionStart. Creates backup before modifying settings. Restart all Claude Code sessions after registration to activate new hooks.

## Configuration

**Recovery registry:** `config/recovery-registry.json`

Three-tier fallback system:
1. Global settings in top-level `hook_settings` object
2. Per-agent overrides in `agents[].hook_settings`
3. Hardcoded defaults in hook scripts

See README.md for full registry schema (agent fields, hook_settings fields, session keys).

**System prompt:** `config/default-system-prompt.txt`

Replacement model: per-agent `system_prompt` in registry replaces default entirely (not appends). CLI `--system-prompt` override takes precedence over both.

**Hooks:** Registered in `~/.claude/settings.json` via `scripts/register-hooks.sh`

## Notes

- Recovery runbook and systemd setup documented in README.md
- No Python dependency: all registry operations use jq
- Hook system replaces old polling architecture (autoresponder, hook-watcher deleted in phase 04)
