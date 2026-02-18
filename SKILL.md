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

Hooks fire on Claude Code events (Stop, Notification, SessionEnd, PreCompact, PreToolUse, PostToolUse) and send structured wake messages to the OpenClaw agent. The agent inspects session state, decides next action, and drives the TUI using `menu-driver.sh`.

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

**pre-tool-use-hook.sh** - Fires when Claude calls AskUserQuestion (forwards structured question data to OpenClaw)

**post-tool-use-hook.sh** - Fires after AskUserQuestion completes (forwards selected answer and tool_use_id to OpenClaw for lifecycle correlation)

All 7 hooks:
- Exit in <5ms for non-managed sessions
- Support async (default) or bidirectional mode via `hook_settings.hook_mode` (PreToolUse and PostToolUse are async-only)
- Use three-tier fallback for configuration: per-agent > global > hardcoded defaults
- Log structured JSONL records per-session via `write_hook_event_record`

### Shared Libraries

**lib/hook-utils.sh** - Shared functions sourced by all hook scripts

Contains 6 functions: `lookup_agent_in_registry`, `extract_last_assistant_response`, `extract_pane_diff`, `format_ask_user_questions`, `write_hook_event_record`, `deliver_async_with_logging`. No side effects on source.

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

**diagnose-hooks.sh** - End-to-end hook chain diagnostic for a registered agent

```bash
scripts/diagnose-hooks.sh <agent-name> [--send-test-wake]
```

Tests 11 steps: hook registration, script permissions, registry entry, tmux session, TMUX propagation, session name resolution, registry lookup, openclaw binary, debug logs, JSONL log analysis, and optional test wake.

**install-logrotate.sh** - Install logrotate config for hook log rotation

```bash
scripts/install-logrotate.sh
```

Installs `config/logrotate.conf` to `/etc/logrotate.d/gsd-code-skill` via sudo tee. Uses copytruncate for safe rotation while hook scripts hold open file descriptors. Daily rotation, 7-day retention, compress with delaycompress.

**register-hooks.sh** - Idempotent hook registration in ~/.claude/settings.json

```bash
scripts/register-hooks.sh
```

Registers all 7 hook events (Stop, Notification [idle_prompt + permission_prompt], SessionEnd, PreCompact, PreToolUse [AskUserQuestion], PostToolUse [AskUserQuestion]) and removes obsolete `gsd-session-hook.sh` from SessionStart. Creates backup before modifying settings. Restart all Claude Code sessions after registration to activate new hooks.

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

**Logrotate:** `config/logrotate.conf`

Template for log rotation. Install via `scripts/install-logrotate.sh` (requires sudo). Uses copytruncate to safely rotate while hook scripts hold open file descriptors.

## v2.0 Changes

**Wake message format (breaking):** `[PANE CONTENT]` replaced by `[CONTENT]` section. Content is now extracted from Claude's transcript JSONL (primary) or pane diff (fallback) instead of raw pane dump. Downstream parsers expecting `[PANE CONTENT]` must update to `[CONTENT]`.

**Content extraction chain:** transcript text (from `transcript_path` JSONL) -> pane diff (only new lines) -> raw pane tail (last 10 lines). First successful extraction wins.

**AskUserQuestion forwarding:** When Claude calls AskUserQuestion, a PreToolUse hook sends structured question data to OpenClaw before the TUI renders. This is async and never blocks.

**Minimum Claude Code version:** >= 2.0.76 (PreToolUse hook support and AskUserQuestion bug fix).

## v3.0 Changes

**Structured JSONL logging:** All 7 hooks emit per-session JSONL records (`logs/{session}.jsonl`) with timestamp, hook_script, trigger, outcome, duration_ms, and hook-specific extra fields. Plain-text debug logs (`logs/{session}.log`) are preserved in parallel.

**PostToolUse hook (new):** Fires after AskUserQuestion completes. Logs `answer_selected` and `tool_use_id` for lifecycle correlation with the PreToolUse record. Always async, always notification-only.

**Logrotate:** `config/logrotate.conf` with copytruncate handles both `*.jsonl` and `*.log` files. Install via `scripts/install-logrotate.sh`.

**Diagnostics:** `scripts/diagnose-hooks.sh` now includes JSONL log analysis (Step 10) showing recent events, outcome distribution, hook script distribution, non-delivered event detection, and duration stats.

**Minimum Claude Code version:** >= 2.0.76 (PostToolUse hook support added in same version as PreToolUse).

## Notes

- Recovery runbook and systemd setup documented in README.md
- No Python dependency: all registry operations use jq
- Hook system replaces old polling architecture (autoresponder, hook-watcher deleted in phase 04)
